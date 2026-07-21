defmodule PermitEx do
  @moduledoc """
  Role and permission management for Ecto and Phoenix applications.

  `PermitEx` keeps the core authorization model intentionally small:
  users receive roles globally or inside an optional context, roles receive
  permissions, and permissions are checked against the current scope.

  Users always receive permissions **through roles** — there is no direct
  user-permission assignment.

  ## Atom safety

  Permission and role identifiers can be passed as atoms for convenience
  (`can?(scope, :orders_manage)`), but atoms must always be **compile-time
  literals**. Never derive them from user input via `String.to_atom/1` — the
  atom table is not garbage-collected and exhausting it crashes the VM. Use
  strings for any value that originates from user input or external data.

  ## Policy contract

  `allowed?/4` and `authorize/4` accept an optional `:policy` module implementing
  `PermitEx.Policy`. The policy callback receives the full `opts` keyword list.
  Unexpected return values or raised exceptions propagate to the caller — wrap
  your policy in a `try/rescue` if you need guaranteed fail-closed semantics.

  ## Optional features (all off by default)

      config :permit_ex,
        cache: true,
        cache_ttl: :timer.minutes(5),
        wildcards: true,
        super_roles: ["super_admin"]
  """

  import Ecto.Query

  alias PermitEx.{Cache, Config, Permission, Role, RolePermission, Telemetry, UserRole}

  @type permission :: String.t() | atom()
  @type role :: Role.t() | Ecto.UUID.t() | String.t()
  @type scope :: %{optional(:permissions) => Enumerable.t(), optional(:roles) => Enumerable.t()}

  # ---------------------------------------------------------------------------
  # Checks
  # ---------------------------------------------------------------------------

  @doc """
  Returns true when the given scope or permission collection includes `permission`.

  When `config :permit_ex, wildcards: true`, granted permissions may use `*`
  (`orders:*` or `*`). When `super_roles` is configured and the scope has one
  of those roles, every permission check succeeds.
  """
  def can?(scope_or_permissions, permission)

  def can?(%{permissions: permissions} = scope, permission) do
    super_role?(scope) or permission_granted?(permissions, permission)
  end

  def can?(%MapSet{} = permissions, permission), do: permission_granted?(permissions, permission)

  def can?(permissions, permission) when is_list(permissions),
    do: permission_granted?(permissions, permission)

  def can?(_scope_or_permissions, _permission), do: false

  @doc "Alias for `can?/2`."
  def has_permission?(scope_or_permissions, permission),
    do: can?(scope_or_permissions, permission)

  @doc "Returns true when at least one of the permissions is granted."
  def can_any?(scope_or_permissions, permissions) when is_list(permissions) do
    Enum.any?(permissions, &can?(scope_or_permissions, &1))
  end

  @doc "Returns true when every permission is granted."
  def can_all?(scope_or_permissions, permissions) when is_list(permissions) do
    Enum.all?(permissions, &can?(scope_or_permissions, &1))
  end

  @doc "Returns true when the given scope or role collection includes `role`."
  def has_role?(scope_or_roles, role)

  def has_role?(%{roles: roles}, role), do: role_granted?(roles, role)

  def has_role?(roles, role) when is_list(roles), do: role_granted?(roles, role)

  def has_role?(%MapSet{} = roles, role), do: MapSet.member?(roles, normalize_role(role))

  def has_role?(_scope_or_roles, _role), do: false

  @doc "Returns true when at least one of the roles is present."
  def has_any_role?(scope_or_roles, roles) when is_list(roles) do
    Enum.any?(roles, &has_role?(scope_or_roles, &1))
  end

  @doc "Returns true when every role is present."
  def has_all_roles?(scope_or_roles, roles) when is_list(roles) do
    Enum.all?(roles, &has_role?(scope_or_roles, &1))
  end

  @doc "Returns `:ok` or `{:error, :unauthorized}` for command-style flows."
  def authorize(scope_or_permissions, permission) do
    case can?(scope_or_permissions, permission) do
      true -> :ok
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Checks a permission and an optional resource policy.

  Returns `:ok` or `{:error, reason}`. Pass a policy with `:policy`.

      PermitEx.authorize(scope, "orders:manage", order, policy: MyApp.OrderPolicy)
      PermitEx.authorize(scope, "orders:manage", policy: MyApp.OrderPolicy, resource: order)
  """
  def authorize(scope, permission, resource_or_opts, opts \\ [])

  def authorize(scope, permission, opts, extra) when is_list(opts) and is_list(extra) do
    merged = Keyword.merge(opts, extra)
    do_authorize(scope, permission, Keyword.get(merged, :resource), merged)
  end

  def authorize(scope, permission, resource, opts) when is_list(opts) do
    do_authorize(scope, permission, resource, opts)
  end

  @doc "Returns `:ok` or `{:error, :unauthorized}` when the scope has the role."
  def authorize_role(scope_or_roles, role) do
    case has_role?(scope_or_roles, role) do
      true -> :ok
      false -> {:error, :unauthorized}
    end
  end

  @doc """
  Checks a permission and an optional resource policy.

  Pass a policy module with `:policy`. The policy module must implement
  `c:PermitEx.Policy.authorize/3`. Full `opts` are forwarded to the policy.
  """
  def allowed?(scope, permission, resource \\ nil, opts \\ []) do
    case do_authorize(scope, permission, resource, opts) do
      :ok -> true
      {:error, _} -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Permissions CRUD
  # ---------------------------------------------------------------------------

  @doc "Creates a permission."
  def create_permission(attrs, opts \\ []) do
    repo(opts).insert(Permission.changeset(%Permission{}, stringify_keys(attrs)))
  end

  @doc "Creates or updates a permission by name."
  def upsert_permission(name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    attrs = attrs |> stringify_keys() |> Map.put("name", name)

    repo(opts).insert(
      Permission.changeset(%Permission{}, attrs),
      on_conflict: {:replace, [:description, :updated_at]},
      conflict_target: :name
    )
  end

  @doc "Updates a permission."
  def update_permission(%Permission{} = permission, attrs, opts \\ []) do
    permission
    |> Permission.changeset(stringify_keys(attrs))
    |> repo(opts).update()
  end

  @doc "Gets a permission by id."
  def get_permission(id, opts \\ []) when is_binary(id) do
    repo(opts).get(Permission, id)
  end

  @doc "Lists permissions ordered by name."
  def list_permissions(opts \\ []) do
    repo(opts).all(from(p in Permission, order_by: p.name))
  end

  @doc "Gets a permission by name."
  def get_permission_by_name(name, opts \\ []) when is_binary(name) do
    repo(opts).get_by(Permission, name: name)
  end

  @doc "Deletes a permission."
  def delete_permission(%Permission{} = permission, opts \\ []) do
    Telemetry.span_result([:permit_ex, :mutation], %{operation: :delete_permission}, fn ->
      result = repo(opts).delete(permission)
      Cache.invalidate_all()
      result
    end)
  end

  # ---------------------------------------------------------------------------
  # Roles CRUD
  # ---------------------------------------------------------------------------

  @doc "Creates a global role or a context role when `context_id` is present."
  def create_role(attrs, opts \\ []) do
    repo(opts).insert(Role.changeset(%Role{}, stringify_keys(attrs)))
  end

  @doc "Creates or updates a global role by name."
  def upsert_role(name, attrs \\ %{}, opts \\ []) when is_binary(name) do
    attrs = attrs |> stringify_keys() |> Map.put("name", name)

    repo(opts).insert(
      Role.changeset(%Role{}, attrs),
      on_conflict: {:replace, [:description, :locked, :updated_at]},
      conflict_target: {:unsafe_fragment, "(name) WHERE context_id IS NULL"},
      returning: [:id]
    )
  end

  @doc "Creates or updates a context role by name."
  def upsert_context_role(name, context_id, attrs \\ %{}, opts \\ [])
      when is_binary(name) and (is_binary(context_id) or is_integer(context_id)) do
    attrs =
      attrs |> stringify_keys() |> Map.put("name", name) |> Map.put("context_id", context_id)

    repo(opts).insert(
      Role.changeset(%Role{}, attrs),
      on_conflict: {:replace, [:description, :locked, :updated_at]},
      conflict_target: {:unsafe_fragment, "(context_id, name) WHERE context_id IS NOT NULL"},
      returning: [:id]
    )
  end

  @doc "Updates a role. Locked roles require `force?: true`."
  def update_role(%Role{} = role, attrs, opts \\ []) do
    with :ok <- ensure_role_unlocked(role, opts) do
      role
      |> Role.changeset(stringify_keys(attrs))
      |> repo(opts).update()
      |> tap_invalidate_all()
    end
  end

  @doc "Gets a role by id."
  def get_role_by_id(id, opts \\ []) when is_binary(id) do
    repo(opts).get(Role, id)
  end

  @doc """
  Returns a map of role name to permission names for the given context.

  Useful for rendering admin permission matrices and exposing role definitions
  via API. Roles with no permissions appear with an empty list.

      PermitEx.role_matrix()
      #=> %{"admin" => ["orders:manage", "orders:view"], "viewer" => ["orders:view"]}

      PermitEx.role_matrix(workspace.id)
  """
  def role_matrix(context_id \\ nil, opts \\ []) do
    from(r in Role,
      left_join: rp in RolePermission,
      on: rp.role_id == r.id,
      left_join: p in Permission,
      on: p.id == rp.permission_id,
      order_by: [asc: r.name, asc: p.name],
      select: {r.name, p.name}
    )
    |> scope_roles(context_id)
    |> repo(opts).all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {role, perms} -> {role, Enum.reject(perms, &is_nil/1)} end)
  end

  @doc "Lists global roles and roles for the given context, with permissions preloaded."
  def list_roles(context_id \\ nil, opts \\ []) do
    Role
    |> scope_roles(context_id)
    |> order_by([r], asc: r.name)
    |> preload([:permissions])
    |> repo(opts).all()
  end

  @doc "Gets a global or context-specific role by name."
  def get_role_by_name(name, context_id \\ nil, opts \\ []) when is_binary(name) do
    repo = repo(opts)

    case find_role_id({:name, name, name}, repo, context_id) do
      nil -> nil
      role_id -> repo.get(Role, role_id)
    end
  end

  @doc "Lists roles that belong to one context."
  def roles_for_context(context_id, opts \\ [])
      when is_binary(context_id) or is_integer(context_id) do
    Role
    |> where([r], r.context_id == ^context_id)
    |> order_by([r], asc: r.name)
    |> repo(opts).all()
  end

  @doc """
  Deletes a role.

  Locked roles return `{:error, :role_locked}` unless `force?: true` is passed.
  """
  def delete_role(%Role{} = role, opts \\ []) do
    with :ok <- ensure_role_unlocked(role, opts) do
      Telemetry.span_result([:permit_ex, :mutation], %{operation: :delete_role}, fn ->
        result = repo(opts).delete(role)
        Cache.invalidate_all()
        result
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Role permissions
  # ---------------------------------------------------------------------------

  @doc "Lists permissions assigned to a role."
  def list_role_permissions(role_ref, opts \\ []) do
    repo = repo(opts)

    with %Role{} = role <- resolve_role(role_ref, repo, context_from_opts(opts)) do
      from(rp in RolePermission,
        join: p in Permission,
        on: p.id == rp.permission_id,
        where: rp.role_id == ^role.id,
        order_by: p.name,
        select: p
      )
      |> repo.all()
    else
      nil -> []
    end
  end

  @doc """
  Adds one permission to a role without removing existing ones.

  Locked roles require `force?: true`.
  """
  def give_permission(role_ref, permission, opts \\ []) do
    give_permissions(role_ref, [permission], opts)
  end

  @doc """
  Adds many permissions to a role without removing existing ones.

  Locked roles require `force?: true`.
  """
  def give_permissions(role_ref, permissions, opts \\ []) when is_list(permissions) do
    repo = repo(opts)

    with %Role{} = role <- resolve_role(role_ref, repo, context_from_opts(opts)),
         :ok <- ensure_role_unlocked(role, opts),
         {:ok, permission_ids} <- resolve_permission_ids(permissions, repo, opts) do
      Telemetry.span_result([:permit_ex, :mutation], %{operation: :give_permissions}, fn ->
        entries =
          Enum.map(permission_ids, fn permission_id ->
            %{role_id: role.id, permission_id: permission_id, inserted_at: now()}
          end)

        {count, _} =
          insert_all_if_any(repo, RolePermission, entries,
            on_conflict: :nothing,
            conflict_target: [:role_id, :permission_id]
          )

        Cache.invalidate_all()
        {:ok, count}
      end)
    else
      nil -> {:error, :role_not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Removes one permission from a role.

  Locked roles require `force?: true`.
  """
  def revoke_permission(role_ref, permission, opts \\ []) do
    revoke_permissions(role_ref, [permission], opts)
  end

  @doc """
  Removes many permissions from a role.

  Locked roles require `force?: true`.
  """
  def revoke_permissions(role_ref, permissions, opts \\ []) when is_list(permissions) do
    repo = repo(opts)

    with %Role{} = role <- resolve_role(role_ref, repo, context_from_opts(opts)),
         :ok <- ensure_role_unlocked(role, opts),
         {:ok, permission_ids} <- resolve_permission_ids(permissions, repo, opts) do
      Telemetry.span_result([:permit_ex, :mutation], %{operation: :revoke_permissions}, fn ->
        {count, _} =
          from(rp in RolePermission,
            where: rp.role_id == ^role.id and rp.permission_id in ^permission_ids
          )
          |> repo.delete_all()

        Cache.invalidate_all()
        {:ok, count}
      end)
    else
      nil -> {:error, :role_not_found}
      {:error, _} = error -> error
    end
  end

  @doc """
  Replaces all permissions assigned to a role.

  Accepts a role struct, role id, or role name. Permissions can be names, ids,
  atoms, or `%PermitEx.Permission{}` structs. Missing permissions return
  `{:error, {:permissions_not_found, missing}}` unless `allow_missing?: true`
  is passed.

  Locked roles require `force?: true`.
  """
  def sync_role_permissions(role_ref, permissions, opts \\ []) when is_list(permissions) do
    repo = repo(opts)

    with %Role{} = role <- resolve_role(role_ref, repo, context_from_opts(opts)),
         :ok <- ensure_role_unlocked(role, opts) do
      case resolve_permission_ids(permissions, repo, opts) do
        {:ok, permission_ids} ->
          Telemetry.span_result(
            [:permit_ex, :mutation],
            %{operation: :sync_role_permissions},
            fn ->
              result =
                repo.transaction(fn ->
                  repo.delete_all(from(rp in RolePermission, where: rp.role_id == ^role.id))

                  entries =
                    Enum.map(permission_ids, fn permission_id ->
                      %{role_id: role.id, permission_id: permission_id, inserted_at: now()}
                    end)

                  insert_all_if_any(repo, RolePermission, entries,
                    on_conflict: :nothing,
                    conflict_target: [:role_id, :permission_id]
                  )

                  role
                end)

              Cache.invalidate_all()
              result
            end
          )

        {:error, _reason} = error ->
          error
      end
    else
      nil -> {:error, :role_not_found}
      {:error, _} = error -> error
    end
  end

  @doc "Alias for `sync_role_permissions/3`."
  def sync_permissions(role_ref, permissions, opts \\ []),
    do: sync_role_permissions(role_ref, permissions, opts)

  # ---------------------------------------------------------------------------
  # User roles
  # ---------------------------------------------------------------------------

  @doc "Assigns one role to a user in a context."
  def assign_role(user_id, role_or_id, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    case resolve_role_ids([role_or_id], context_id, repo, opts) do
      {:ok, [role_id]} ->
        Telemetry.span_result([:permit_ex, :mutation], %{operation: :assign_role}, fn ->
          result =
            %UserRole{}
            |> UserRole.changeset(%{user_id: user_id, role_id: role_id, context_id: context_id})
            |> repo.insert(
              on_conflict: :nothing,
              conflict_target: user_role_conflict_target(context_id)
            )

          Cache.invalidate(user_id, context_id)
          result
        end)

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc "Assigns many roles to a user without removing existing roles."
  def assign_roles(user_id, roles, context_id \\ nil, opts \\ []) when is_list(roles) do
    repo = repo(opts)

    case resolve_role_ids(roles, context_id, repo, opts) do
      {:ok, role_ids} ->
        Telemetry.span_result([:permit_ex, :mutation], %{operation: :assign_roles}, fn ->
          entries =
            Enum.map(role_ids, fn role_id ->
              %{user_id: user_id, context_id: context_id, role_id: role_id, inserted_at: now()}
            end)

          {count, _} =
            insert_all_if_any(repo, UserRole, entries,
              on_conflict: :nothing,
              conflict_target: user_role_conflict_target(context_id)
            )

          Cache.invalidate(user_id, context_id)
          {:ok, count}
        end)

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc "Removes one role from a user in a context."
  def revoke_role(user_id, role_or_id, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    case resolve_role_ids([role_or_id], context_id, repo, opts) do
      {:ok, [role_id]} ->
        Telemetry.span_result([:permit_ex, :mutation], %{operation: :revoke_role}, fn ->
          {count, _} =
            UserRole
            |> where([ur], ur.user_id == ^user_id and ur.role_id == ^role_id)
            |> scope_user_roles(context_id)
            |> repo.delete_all()

          Cache.invalidate(user_id, context_id)
          {:ok, count}
        end)

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc """
  Replaces all roles assigned to a user in a context.

  This is the Spatie-style `syncRoles` equivalent. It accepts role structs, ids
  or names and leaves the user with exactly the resolved roles.
  """
  def sync_user_roles(user_id, roles, context_id \\ nil, opts \\ []) when is_list(roles) do
    repo = repo(opts)

    case resolve_role_ids(roles, context_id, repo, opts) do
      {:ok, role_ids} ->
        Telemetry.span_result([:permit_ex, :mutation], %{operation: :sync_user_roles}, fn ->
          result =
            repo.transaction(fn ->
              UserRole
              |> where([ur], ur.user_id == ^user_id)
              |> scope_user_roles(context_id)
              |> repo.delete_all()

              entries =
                Enum.map(role_ids, fn role_id ->
                  %{
                    user_id: user_id,
                    context_id: context_id,
                    role_id: role_id,
                    inserted_at: now()
                  }
                end)

              {count, _} =
                insert_all_if_any(repo, UserRole, entries,
                  on_conflict: :nothing,
                  conflict_target: user_role_conflict_target(context_id)
                )

              count
            end)

          Cache.invalidate(user_id, context_id)
          result
        end)

      {:error, {:roles_not_found, _missing}} = error ->
        error
    end
  end

  @doc "Alias for `sync_user_roles/4`."
  def sync_roles(user_id, roles, context_id \\ nil, opts \\ []),
    do: sync_user_roles(user_id, roles, context_id, opts)

  @doc "Loads roles assigned to a user in a context."
  def roles_for(user_id, context_id \\ nil, opts \\ []) do
    from(ur in UserRole,
      join: r in Role,
      on: r.id == ur.role_id,
      where: ur.user_id == ^user_id,
      order_by: r.name,
      select: r
    )
    |> scope_user_roles(context_id)
    |> repo(opts).all()
  end

  @doc "Lists user ids assigned to a role."
  def users_with_role(role_ref, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    with %Role{} = role <- resolve_role(role_ref, repo, context_id) do
      UserRole
      |> where([ur], ur.role_id == ^role.id)
      |> scope_user_roles(context_id)
      |> order_by([ur], asc: ur.user_id)
      |> select([ur], ur.user_id)
      |> repo.all()
    else
      nil -> []
    end
  end

  @doc """
  Lists user ids that have the given permission through any role in the context.
  """
  def users_with_permission(permission_ref, context_id \\ nil, opts \\ []) do
    repo = repo(opts)

    with {:ok, [permission_id]} <- resolve_permission_ids([permission_ref], repo, opts) do
      from(ur in UserRole,
        join: rp in RolePermission,
        on: rp.role_id == ur.role_id,
        where: rp.permission_id == ^permission_id,
        order_by: ur.user_id,
        distinct: true,
        select: ur.user_id
      )
      |> scope_user_roles(context_id)
      |> repo.all()
    else
      {:error, _} -> []
    end
  end

  @doc "Lists role assignments for a user."
  def list_user_roles(user_id, context_id \\ nil, opts \\ []) do
    UserRole
    |> where([ur], ur.user_id == ^user_id)
    |> scope_user_roles(context_id)
    |> order_by([ur], asc: ur.role_id)
    |> repo(opts).all()
  end

  @doc "Loads permission names for the user in a context."
  def permissions_for(user_id, context_id \\ nil, opts \\ []) do
    {_roles, permissions} = scope_data_for(user_id, context_id, opts)
    permissions
  end

  @doc """
  Loads roles and permissions for a user in a single query.

  Results are cached when `config :permit_ex, cache: true`. Pass
  `skip_cache: true` to force a database load.
  """
  def scope_data_for(user_id, context_id \\ nil, opts \\ []) do
    skip_cache? = Keyword.get(opts, :skip_cache, false)

    Telemetry.span(
      [:permit_ex, :scope, :load],
      %{user_id: user_id, context_id: context_id},
      fn ->
        if not skip_cache? do
          case Cache.get(user_id, context_id) do
            {:ok, data} ->
              {data, %{cache_hit: true}}

            :miss ->
              data = load_scope_data(user_id, context_id, opts)
              Cache.put(user_id, context_id, data)
              {data, %{cache_hit: false}}
          end
        else
          data = load_scope_data(user_id, context_id, opts)
          {data, %{cache_hit: false}}
        end
      end
    )
  end

  # ---------------------------------------------------------------------------
  # Context templates & seed
  # ---------------------------------------------------------------------------

  @doc """
  Clones global role templates into a context.

  A global role is any role with `context_id == nil`. The cloned context role
  receives the same name, description, locked flag, and permissions. Existing
  context roles are updated idempotently.

      PermitEx.clone_roles_to_context(workspace.id)
      PermitEx.clone_roles_to_context(workspace.id, roles: ["admin", "viewer"])
  """
  def clone_roles_to_context(context_id, opts \\ [])
      when is_binary(context_id) or is_integer(context_id) do
    repo = repo(opts)
    role_names = Keyword.get(opts, :roles)

    repo.transaction(fn ->
      roles = list_global_role_templates(repo, role_names)
      permissions_by_role_id = batch_permission_names_for_roles(Enum.map(roles, & &1.id), repo)

      Enum.map(roles, fn role ->
        permission_names = Map.get(permissions_by_role_id, role.id, [])

        {:ok, context_role} =
          upsert_context_role(
            role.name,
            context_id,
            %{description: role.description, locked: role.locked},
            repo: repo
          )

        {:ok, _role} =
          sync_role_permissions(
            context_role,
            permission_names,
            opts |> Keyword.put(:repo, repo) |> Keyword.put(:force?, true)
          )

        context_role
      end)
    end)
  end

  @doc "Alias for `clone_roles_to_context/2`."
  def sync_context_roles_from_templates(context_id, opts \\ []),
    do: clone_roles_to_context(context_id, opts)

  @doc """
  Seeds permissions and roles in one transaction.

  Pass `context_id:` to create context roles instead of global templates.

  Expected shape:

      PermitEx.seed!(
        permissions: [
          {"orders:view", "View orders"},
          {"orders:manage", "Manage orders"}
        ],
        roles: [
          {"admin", "Context admin", ["orders:view", "orders:manage"]},
          {"viewer", "Read-only user", ["orders:view"]}
        ]
      )

      PermitEx.seed!(definitions, context_id: workspace.id)
  """
  def seed!(definitions, opts \\ []) when is_list(definitions) do
    repo = repo(opts)
    context_id = Keyword.get(opts, :context_id)

    repo.transaction(fn ->
      definitions
      |> Keyword.get(:permissions, [])
      |> Enum.each(fn {name, description} ->
        {:ok, _permission} = upsert_permission(name, %{description: description}, repo: repo)
      end)

      definitions
      |> Keyword.get(:roles, [])
      |> Enum.each(fn {name, description, permissions} ->
        {:ok, role} =
          if context_id do
            upsert_context_role(name, context_id, %{description: description}, repo: repo)
          else
            upsert_role(name, %{description: description}, repo: repo)
          end

        {:ok, _role} =
          sync_role_permissions(role, permissions, repo: repo, force?: true)
      end)

      :ok
    end)
  end

  @doc """
  Invalidates cached scope data.

  Pass a `context_id` for one scope (`nil` = global). Pass `:all` as the second
  argument to drop every cached scope for that user.
  """
  def invalidate_cache(user_id, context_id \\ nil), do: Cache.invalidate(user_id, context_id)

  @doc "Invalidates the entire scope cache."
  def invalidate_cache_all, do: Cache.invalidate_all()

  def normalize_permission(permission) when is_atom(permission), do: Atom.to_string(permission)
  def normalize_permission(permission) when is_binary(permission), do: permission
  def normalize_permission(permission), do: to_string(permission)

  def normalize_role(%Role{name: name}), do: name
  def normalize_role(role) when is_atom(role), do: Atom.to_string(role)
  def normalize_role(role) when is_binary(role), do: role
  def normalize_role(role), do: to_string(role)

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp do_authorize(scope, permission, resource, opts) do
    start = System.monotonic_time()

    result =
      with true <- can?(scope, permission),
           :ok <- authorize_policy(scope, resource, Keyword.get(opts, :policy), opts) do
        :ok
      else
        false -> {:error, :unauthorized}
        {:error, _reason} = error -> error
      end

    :telemetry.execute(
      [:permit_ex, :authorize, :stop],
      %{duration: System.monotonic_time() - start},
      %{
        permission: normalize_permission(permission),
        result: elem_result(result),
        check: :authorize
      }
    )

    result
  end

  defp elem_result(:ok), do: :ok
  defp elem_result({:error, _}), do: :error

  defp permission_granted?(permissions, permission) do
    normalized = normalize_permission(permission)

    cond do
      collection_member?(permissions, normalized) ->
        true

      Config.wildcards?() ->
        wildcard_match?(permissions, normalized)

      true ->
        false
    end
  end

  defp wildcard_match?(permissions, requested) do
    permissions
    |> to_permission_list()
    |> Enum.any?(fn granted ->
      granted == "*" or resource_wildcard?(granted, requested)
    end)
  end

  defp resource_wildcard?(granted, requested) do
    case String.split(granted, ":", parts: 2) do
      [resource, "*"] ->
        case String.split(requested, ":", parts: 2) do
          [^resource, _action] -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp collection_member?(%MapSet{} = set, value), do: MapSet.member?(set, value)

  defp collection_member?(list, value) when is_list(list) do
    Enum.any?(list, &(normalize_permission(&1) == value))
  end

  defp collection_member?(_, _), do: false

  defp to_permission_list(%MapSet{} = set), do: MapSet.to_list(set)
  defp to_permission_list(list) when is_list(list), do: Enum.map(list, &normalize_permission/1)
  defp to_permission_list(_), do: []

  defp role_granted?(roles, role) when is_list(roles) do
    normalized = normalize_role(role)

    Enum.any?(roles, fn
      %Role{name: name} -> name == normalized
      value -> normalize_role(value) == normalized
    end)
  end

  defp role_granted?(%MapSet{} = roles, role), do: MapSet.member?(roles, normalize_role(role))
  defp role_granted?(_, _), do: false

  defp super_role?(%{roles: roles}) do
    super = Config.super_roles()

    super != [] and
      Enum.any?(super, fn name ->
        role_granted?(roles, name)
      end)
  end

  defp super_role?(_), do: false

  defp load_scope_data(user_id, context_id, opts) do
    rows =
      from(ur in UserRole,
        join: r in Role,
        on: r.id == ur.role_id,
        left_join: rp in RolePermission,
        on: rp.role_id == r.id,
        left_join: p in Permission,
        on: p.id == rp.permission_id,
        where: ur.user_id == ^user_id,
        select: {r, p.name}
      )
      |> scope_user_roles(context_id)
      |> repo(opts).all()

    roles = rows |> Enum.map(&elem(&1, 0)) |> Enum.uniq_by(& &1.id)
    permissions = rows |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> MapSet.new()

    {roles, permissions}
  end

  defp repo(opts), do: Keyword.get(opts, :repo) || Config.repo!()

  defp context_from_opts(opts), do: Keyword.get(opts, :context_id, Keyword.get(opts, :tenant_id))

  defp scope_roles(query, nil), do: where(query, [r], is_nil(r.context_id))

  defp scope_roles(query, context_id) do
    where(query, [r], is_nil(r.context_id) or r.context_id == ^context_id)
  end

  defp scope_user_roles(query, nil), do: where(query, [ur], is_nil(ur.context_id))

  defp scope_user_roles(query, context_id) do
    where(query, [ur], ur.context_id == ^context_id)
  end

  defp user_role_conflict_target(nil) do
    {:unsafe_fragment, "(user_id, role_id) WHERE context_id IS NULL"}
  end

  defp user_role_conflict_target(_context_id) do
    {:unsafe_fragment, "(user_id, context_id, role_id) WHERE context_id IS NOT NULL"}
  end

  defp resolve_role(%Role{} = role, _repo, _context_id), do: role

  defp resolve_role(role_ref, repo, context_id) when is_binary(role_ref) do
    case resolve_role_ids([role_ref], context_id, repo, []) do
      {:ok, [role_id]} -> repo.get(Role, role_id)
      {:error, _reason} -> nil
    end
  end

  defp ensure_role_unlocked(%Role{locked: true}, opts) do
    if Keyword.get(opts, :force?, false), do: :ok, else: {:error, :role_locked}
  end

  defp ensure_role_unlocked(%Role{}, _opts), do: :ok

  defp resolve_permission_ids(permissions, repo, opts) do
    permissions
    |> Enum.map(&permission_lookup/1)
    |> resolve_permission_lookups(repo, Keyword.get(opts, :allow_missing?, false))
  end

  defp resolve_role_ids(roles, context_id, repo, opts) do
    roles
    |> Enum.map(&role_lookup/1)
    |> resolve_role_lookups(repo, context_id, Keyword.get(opts, :allow_missing?, false))
  end

  defp permission_lookup(%Permission{id: id}), do: {:id, id, id}
  defp permission_lookup(value) when is_atom(value), do: {:name, Atom.to_string(value), value}

  defp permission_lookup(value) when is_binary(value) do
    {kind, resolved} = lookup_value(value)
    {kind, resolved, value}
  end

  defp role_lookup(%Role{id: id}), do: {:id, id, id}
  defp role_lookup(value) when is_atom(value), do: {:name, Atom.to_string(value), value}

  defp role_lookup(value) when is_binary(value) do
    {kind, resolved} = lookup_value(value)
    {kind, resolved, value}
  end

  defp lookup_value(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:id, uuid}
      :error -> {:name, value}
    end
  end

  defp resolve_permission_lookups(lookups, repo, allow_missing?) do
    {id_lookups, name_lookups} = Enum.split_with(lookups, &match?({:id, _, _}, &1))

    found =
      Map.merge(
        batch_find_permissions_by_id(id_lookups, repo),
        batch_find_permissions_by_name(name_lookups, repo)
      )

    {ids, missing} =
      Enum.reduce(lookups, {[], []}, fn {kind, value, label}, {ids, missing} ->
        case Map.fetch(found, {kind, value}) do
          {:ok, id} -> {[id | ids], missing}
          :error -> {ids, [label | missing]}
        end
      end)

    resolved_or_missing(ids, missing, :permissions_not_found, allow_missing?)
  end

  defp resolve_role_lookups(lookups, repo, context_id, allow_missing?) do
    {id_lookups, name_lookups} = Enum.split_with(lookups, &match?({:id, _, _}, &1))

    found =
      Map.merge(
        batch_find_roles_by_id(id_lookups, repo),
        batch_find_roles_by_name(name_lookups, repo, context_id)
      )

    {ids, missing} =
      Enum.reduce(lookups, {[], []}, fn {kind, value, label}, {ids, missing} ->
        case Map.fetch(found, {kind, value}) do
          {:ok, id} -> {[id | ids], missing}
          :error -> {ids, [label | missing]}
        end
      end)

    resolved_or_missing(ids, missing, :roles_not_found, allow_missing?)
  end

  defp batch_find_permissions_by_id([], _repo), do: %{}

  defp batch_find_permissions_by_id(lookups, repo) do
    ids = Enum.map(lookups, fn {:id, id, _} -> id end)

    Permission
    |> where([p], p.id in ^ids)
    |> select([p], p.id)
    |> repo.all()
    |> Map.new(&{{:id, &1}, &1})
  end

  defp batch_find_permissions_by_name([], _repo), do: %{}

  defp batch_find_permissions_by_name(lookups, repo) do
    names = Enum.map(lookups, fn {:name, name, _} -> name end)

    Permission
    |> where([p], p.name in ^names)
    |> select([p], {p.name, p.id})
    |> repo.all()
    |> Map.new(fn {name, id} -> {{:name, name}, id} end)
  end

  defp batch_find_roles_by_id([], _repo), do: %{}

  defp batch_find_roles_by_id(lookups, repo) do
    ids = Enum.map(lookups, fn {:id, id, _} -> id end)

    Role
    |> where([r], r.id in ^ids)
    |> select([r], r.id)
    |> repo.all()
    |> Map.new(&{{:id, &1}, &1})
  end

  defp batch_find_roles_by_name([], _repo, _context_id), do: %{}

  defp batch_find_roles_by_name(lookups, repo, nil) do
    names = Enum.map(lookups, fn {:name, name, _} -> name end)

    Role
    |> where([r], r.name in ^names and is_nil(r.context_id))
    |> select([r], {r.name, r.id})
    |> repo.all()
    |> Map.new(fn {name, id} -> {{:name, name}, id} end)
  end

  defp batch_find_roles_by_name(lookups, repo, context_id) do
    names = Enum.map(lookups, fn {:name, name, _} -> name end)

    Role
    |> where([r], r.name in ^names and (r.context_id == ^context_id or is_nil(r.context_id)))
    |> select([r], {r.name, r.id, r.context_id})
    |> repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {name, entries} ->
      {_, id, _} =
        Enum.min_by(entries, fn {_, _, ctx} ->
          case ctx do
            nil -> 1
            _ -> 0
          end
        end)

      {{:name, name}, id}
    end)
  end

  defp batch_permission_names_for_roles([], _repo), do: %{}

  defp batch_permission_names_for_roles(role_ids, repo) do
    from(rp in RolePermission,
      join: p in Permission,
      on: p.id == rp.permission_id,
      where: rp.role_id in ^role_ids,
      select: {rp.role_id, p.name}
    )
    |> repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp find_role_id({:name, name, _label}, repo, nil) do
    Role
    |> where([r], r.name == ^name and is_nil(r.context_id))
    |> select([r], r.id)
    |> repo.one()
  end

  defp find_role_id({:name, name, _label}, repo, context_id) do
    Role
    |> where([r], r.name == ^name and (r.context_id == ^context_id or is_nil(r.context_id)))
    |> order_by([r], asc: is_nil(r.context_id))
    |> limit(1)
    |> select([r], r.id)
    |> repo.one()
  end

  defp list_global_role_templates(repo, nil) do
    Role
    |> where([r], is_nil(r.context_id))
    |> order_by([r], asc: r.name)
    |> repo.all()
  end

  defp list_global_role_templates(repo, role_names) when is_list(role_names) do
    normalized_names = Enum.map(role_names, &normalize_role/1)

    Role
    |> where([r], is_nil(r.context_id) and r.name in ^normalized_names)
    |> order_by([r], asc: r.name)
    |> repo.all()
  end

  defp authorize_policy(_scope, _resource, nil, _opts), do: :ok

  defp authorize_policy(scope, resource, policy, opts) when is_atom(policy) do
    case policy.authorize(scope, resource, opts) do
      :ok -> :ok
      true -> :ok
      false -> {:error, :unauthorized}
      {:error, _reason} = error -> error
    end
  end

  defp resolved_or_missing(ids, [], _reason, _allow_missing?),
    do: {:ok, ids |> Enum.reverse() |> Enum.uniq()}

  defp resolved_or_missing(ids, _missing, _reason, true),
    do: {:ok, ids |> Enum.reverse() |> Enum.uniq()}

  defp resolved_or_missing(_ids, missing, reason, false) do
    {:error, {reason, missing |> Enum.reverse() |> Enum.uniq()}}
  end

  defp insert_all_if_any(_repo, _schema, [], _opts), do: {0, nil}
  defp insert_all_if_any(repo, schema, entries, opts), do: repo.insert_all(schema, entries, opts)

  defp tap_invalidate_all({:ok, _} = result) do
    Cache.invalidate_all()
    result
  end

  defp tap_invalidate_all(other), do: other

  defp now, do: DateTime.utc_now(:microsecond)

  defp stringify_keys(attrs) when is_map(attrs) do
    Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
  end
end
