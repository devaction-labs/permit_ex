defmodule PermitEx.Scope do
  @moduledoc """
  Authorization scope loaded from PermitEx role assignments.

  Use this struct directly or merge its `roles` and `permissions` into your
  application's own Phoenix scope.
  """

  alias PermitEx.Role

  defstruct user_id: nil, context_id: nil, roles: [], permissions: MapSet.new(), assigns: %{}

  @type t :: %__MODULE__{
          user_id: term() | nil,
          context_id: term() | nil,
          roles: [Role.t()],
          permissions: MapSet.t(String.t()),
          assigns: map()
        }

  @doc """
  Builds a `%PermitEx.Scope{}` for the user and optional context.

  Accepts ids, structs with an `:id` field, or maps with an `"id"` key.
  """
  def for_user(user, context \\ nil, opts \\ []) do
    user_id = id_from(user)
    context_id = id_from(context)

    {roles, permissions} = PermitEx.scope_data_for(user_id, context_id, opts)

    %__MODULE__{
      user_id: user_id,
      context_id: context_id,
      roles: roles,
      permissions: permissions
    }
  end

  @doc """
  Reloads roles and permissions for an existing scope, preserving `assigns`.

  Useful after role changes in long-lived LiveViews.
  """
  def reload(scope, opts \\ [])

  def reload(%__MODULE__{} = scope, opts) do
    {roles, permissions} =
      PermitEx.scope_data_for(
        scope.user_id,
        scope.context_id,
        Keyword.put(opts, :skip_cache, true)
      )

    %{scope | roles: roles, permissions: permissions}
  end

  def reload(%{} = scope, opts) do
    user_id = Map.get(scope, :user_id) || Map.get(scope, "user_id")
    context_id = Map.get(scope, :context_id) || Map.get(scope, "context_id")

    {roles, permissions} =
      PermitEx.scope_data_for(user_id, context_id, Keyword.put(opts, :skip_cache, true))

    scope
    |> put_value(:roles, roles)
    |> put_value(:permissions, permissions)
  end

  @doc """
  Merges PermitEx authorization data into an existing map or struct.
  """
  def put_permission_data(scope, user, context \\ nil, opts \\ []) do
    permission_scope = for_user(user, context, opts)

    scope
    |> put_value(:roles, permission_scope.roles)
    |> put_value(:permissions, permission_scope.permissions)
  end

  @doc """
  Puts a value into the scope's `assigns` map.

  Works with `%PermitEx.Scope{}` and plain maps that already have `:assigns`.
  """
  def put_assign(%__MODULE__{} = scope, key, value) do
    %{scope | assigns: Map.put(scope.assigns, key, value)}
  end

  def put_assign(%{} = scope, key, value) do
    assigns = Map.get(scope, :assigns, %{})
    put_value(scope, :assigns, Map.put(assigns, key, value))
  end

  defp id_from(%{id: id}), do: id
  defp id_from(%{"id" => id}), do: id
  defp id_from(id) when is_binary(id) or is_integer(id), do: id
  defp id_from(nil), do: nil

  defp put_value(%_struct{} = scope, key, value) do
    struct(scope, %{key => value})
  end

  defp put_value(scope, key, value) when is_map(scope) do
    Map.put(scope, key, value)
  end
end
