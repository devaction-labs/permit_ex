defmodule PermitExTest do
  use ExUnit.Case, async: true

  import Plug.Test

  defmodule OwnerPolicy do
    @behaviour PermitEx.Policy

    def authorize(scope, resource, _opts), do: scope.user_id == resource.owner_id
  end

  defmodule OptPolicy do
    @behaviour PermitEx.Policy

    def authorize(_scope, _resource, opts), do: Keyword.get(opts, :allow, false)
  end

  describe "can?/2" do
    test "checks map scopes with MapSet permissions" do
      scope = %{permissions: MapSet.new(["orders:view", "orders:manage"])}

      assert PermitEx.can?(scope, "orders:view")
      refute PermitEx.can?(scope, "settings:manage")
    end

    test "checks list permissions and normalizes atoms" do
      assert PermitEx.can?(["manage_members"], :manage_members)
      assert PermitEx.can?([:manage_members], "manage_members")
    end

    test "returns false for nil scope" do
      refute PermitEx.can?(nil, "orders:view")
    end

    test "returns false for empty permissions" do
      refute PermitEx.can?(%{permissions: MapSet.new()}, "orders:view")
      refute PermitEx.can?(%{permissions: []}, "orders:view")
    end
  end

  describe "authorize/2" do
    test "returns tagged authorization results" do
      assert PermitEx.authorize(["orders:view"], "orders:view") == :ok
      assert PermitEx.authorize([], "orders:view") == {:error, :unauthorized}
    end
  end

  describe "can_any?/can_all?" do
    test "checks multiple permissions" do
      scope = %{permissions: MapSet.new(["orders:view"])}

      assert PermitEx.can_any?(scope, ["orders:view", "orders:manage"])
      refute PermitEx.can_all?(scope, ["orders:view", "orders:manage"])
      assert PermitEx.can_all?(scope, ["orders:view"])
    end
  end

  describe "has_role?/2" do
    test "checks scopes with role names" do
      scope = %{roles: ["admin", "billing"]}

      assert PermitEx.has_role?(scope, :admin)
      refute PermitEx.has_role?(scope, "viewer")
    end

    test "returns false for nil scope" do
      refute PermitEx.has_role?(nil, "admin")
    end
  end

  describe "has_any_role?/has_all_roles?/authorize_role" do
    test "checks multiple roles" do
      scope = %{roles: ["admin", "billing"]}

      assert PermitEx.has_any_role?(scope, ["admin", "viewer"])
      assert PermitEx.has_all_roles?(scope, ["admin", "billing"])
      refute PermitEx.has_all_roles?(scope, ["admin", "viewer"])
      assert PermitEx.authorize_role(scope, "admin") == :ok
      assert PermitEx.authorize_role(scope, "viewer") == {:error, :unauthorized}
    end
  end

  describe "normalize helpers" do
    test "normalizes permission and role inputs" do
      assert PermitEx.normalize_permission(:orders_manage) == "orders_manage"
      assert PermitEx.normalize_role(:admin) == "admin"
    end
  end

  describe "allowed?/4 and authorize/4" do
    test "combines RBAC and resource policy checks" do
      scope = %{user_id: "user-1", permissions: ["orders:manage"]}

      assert PermitEx.allowed?(scope, "orders:manage", %{owner_id: "user-1"}, policy: OwnerPolicy)

      refute PermitEx.allowed?(scope, "orders:manage", %{owner_id: "user-2"}, policy: OwnerPolicy)

      assert PermitEx.authorize(scope, "orders:manage", %{owner_id: "user-1"},
               policy: OwnerPolicy
             ) ==
               :ok

      assert PermitEx.authorize(scope, "orders:manage", %{owner_id: "user-2"},
               policy: OwnerPolicy
             ) ==
               {:error, :unauthorized}
    end

    test "returns false when permission check fails regardless of policy" do
      scope = %{user_id: "user-1", permissions: []}

      refute PermitEx.allowed?(scope, "orders:manage", %{owner_id: "user-1"}, policy: OwnerPolicy)
    end

    test "forwards opts to the policy module" do
      scope = %{permissions: ["orders:view"]}

      assert PermitEx.allowed?(scope, "orders:view", %{}, policy: OptPolicy, allow: true)
      refute PermitEx.allowed?(scope, "orders:view", %{}, policy: OptPolicy, allow: false)
    end
  end

  describe "wildcards" do
    setup do
      previous = Application.get_env(:permit_ex, :wildcards)
      Application.put_env(:permit_ex, :wildcards, true)
      on_exit(fn -> Application.put_env(:permit_ex, :wildcards, previous) end)
      :ok
    end

    test "orders:* matches orders:view" do
      scope = %{permissions: MapSet.new(["orders:*"])}

      assert PermitEx.can?(scope, "orders:view")
      assert PermitEx.can?(scope, "orders:manage")
      refute PermitEx.can?(scope, "settings:view")
    end

    test "* matches every permission" do
      scope = %{permissions: MapSet.new(["*"])}

      assert PermitEx.can?(scope, "orders:view")
      assert PermitEx.can?(scope, "settings:manage")
    end
  end

  describe "super_roles" do
    setup do
      previous = Application.get_env(:permit_ex, :super_roles)
      Application.put_env(:permit_ex, :super_roles, ["super_admin"])
      on_exit(fn -> Application.put_env(:permit_ex, :super_roles, previous) end)
      :ok
    end

    test "super role grants every permission" do
      scope = %{roles: ["super_admin"], permissions: MapSet.new()}

      assert PermitEx.can?(scope, "orders:manage")
      assert PermitEx.can?(scope, "settings:delete")
    end

    test "non-super role still requires permissions" do
      scope = %{roles: ["viewer"], permissions: MapSet.new(["orders:view"])}

      assert PermitEx.can?(scope, "orders:view")
      refute PermitEx.can?(scope, "orders:manage")
    end
  end

  describe "Scope.put_assign/3" do
    test "stores extra data on assigns" do
      scope = %PermitEx.Scope{} |> PermitEx.Scope.put_assign(:workspace, "ws-1")

      assert scope.assigns.workspace == "ws-1"
    end
  end

  describe "Guard.authorized?/2" do
    test "supports role and permission combinations" do
      scope = %{roles: ["admin"], permissions: MapSet.new(["orders:view", "orders:manage"])}

      assert PermitEx.Guard.authorized?(scope,
               role: "admin",
               all_permissions: ["orders:view", "orders:manage"]
             )

      refute PermitEx.Guard.authorized?(scope,
               role: "admin",
               all_permissions: ["settings:manage"]
             )
    end

    test "supports any_permissions — passes when at least one matches" do
      scope = %{permissions: MapSet.new(["orders:view"]), roles: []}

      assert PermitEx.Guard.authorized?(scope, any_permissions: ["orders:view", "orders:manage"])

      refute PermitEx.Guard.authorized?(scope,
               any_permissions: ["settings:manage", "users:manage"]
             )
    end

    test "supports any_roles — passes when at least one matches" do
      scope = %{roles: ["viewer"], permissions: MapSet.new()}

      assert PermitEx.Guard.authorized?(scope, any_roles: ["admin", "viewer"])
      refute PermitEx.Guard.authorized?(scope, any_roles: ["admin", "support"])
    end

    test "supports all_roles — requires every role" do
      scope = %{roles: ["admin", "billing"], permissions: MapSet.new()}

      assert PermitEx.Guard.authorized?(scope, all_roles: ["admin", "billing"])
      refute PermitEx.Guard.authorized?(scope, all_roles: ["admin", "billing", "support"])
    end

    test "raises when called with no constraint options" do
      scope = %{permissions: MapSet.new(["orders:view"]), roles: []}

      assert_raise ArgumentError, ~r/at least one of/, fn ->
        PermitEx.Guard.authorized?(scope, assign_key: :my_scope)
      end
    end

    test "raises when called with empty opts" do
      assert_raise ArgumentError, ~r/at least one of/, fn ->
        PermitEx.Guard.authorized?(%{}, [])
      end
    end
  end

  describe "Scope.put_permission_data/4" do
    test "merges roles and permissions into a plain map" do
      scope = %PermitEx.Scope{roles: [], permissions: MapSet.new()}
      map = %{user: "alex"}

      result = Map.merge(map, %{roles: scope.roles, permissions: scope.permissions})

      assert result.user == "alex"
      assert result.roles == []
      assert result.permissions == MapSet.new()
    end
  end

  describe "Plug guards" do
    test "allows authorized connections" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_scope, %{permissions: ["orders:manage"]})

      result = PermitEx.Plug.RequirePermission.call(conn, permission: "orders:manage")

      refute result.halted
    end

    test "halts unauthorized connections" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_scope, %{permissions: []})

      result = PermitEx.Plug.RequirePermission.call(conn, permission: "orders:manage")

      assert result.halted
      assert result.status == 403
      assert result.resp_body == ~s({"error":"forbidden"})
    end

    test "fails closed when scope is nil" do
      conn = conn(:get, "/")

      result = PermitEx.Plug.RequirePermission.call(conn, permission: "orders:manage")

      assert result.halted
      assert result.status == 403
    end

    test "RequireRole halts when role is absent" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_scope, %{roles: ["viewer"]})

      result = PermitEx.Plug.RequireRole.call(conn, role: "admin")

      assert result.halted
    end

    test "RequireAuthorization supports any_permissions" do
      conn =
        :get
        |> conn("/")
        |> Plug.Conn.assign(:current_scope, %{
          permissions: MapSet.new(["orders:view"]),
          roles: []
        })

      result =
        PermitEx.Plug.RequireAuthorization.call(conn,
          any_permissions: ["orders:view", "orders:manage"]
        )

      refute result.halted
    end
  end

  describe "LiveView guards" do
    test "continues authorized sockets" do
      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: %{roles: ["admin"]}}}

      assert {:cont, ^socket} =
               PermitEx.LiveView.RequireRole.on_mount("admin", %{}, %{}, socket)
    end

    test "halts unauthorized sockets" do
      socket = %Phoenix.LiveView.Socket{assigns: %{current_scope: %{roles: []}}}

      assert {:halt, ^socket} =
               PermitEx.LiveView.RequireRole.on_mount("admin", %{}, %{}, socket)
    end

    test "fails closed when scope is nil" do
      socket = %Phoenix.LiveView.Socket{assigns: %{}}

      assert {:halt, _socket} =
               PermitEx.LiveView.RequirePermission.on_mount("orders:manage", %{}, %{}, socket)
    end

    test "RequireAuthorization supports redirect_to and flash" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          flash: %{},
          current_scope: %{roles: [], permissions: MapSet.new()}
        }
      }

      assert {:halt, halted} =
               PermitEx.LiveView.RequireAuthorization.on_mount(
                 [permission: "orders:manage", flash: {:error, "Forbidden"}, redirect_to: "/"],
                 %{},
                 %{},
                 socket
               )

      assert halted.redirected != nil
    end
  end

  describe "Absinthe middleware" do
    test "RequirePermission passes authorized resolution through unchanged" do
      scope = %{permissions: MapSet.new(["orders:manage"]), roles: []}
      resolution = %Absinthe.Resolution{context: %{current_scope: scope}}

      result = PermitEx.Absinthe.RequirePermission.call(resolution, "orders:manage")

      assert result.errors == []
    end

    test "RequirePermission denies unauthorized resolution" do
      scope = %{permissions: MapSet.new(), roles: []}
      resolution = %Absinthe.Resolution{context: %{current_scope: scope}}

      result = PermitEx.Absinthe.RequirePermission.call(resolution, "orders:manage")

      assert result.errors != []
    end

    test "RequirePermission fails closed when scope is missing" do
      resolution = %Absinthe.Resolution{context: %{}}

      result = PermitEx.Absinthe.RequirePermission.call(resolution, "orders:manage")

      assert result.errors != []
    end

    test "RequireRole checks role correctly" do
      scope = %{roles: ["admin"], permissions: MapSet.new()}

      allowed = %Absinthe.Resolution{context: %{current_scope: scope}}

      denied = %Absinthe.Resolution{
        context: %{current_scope: %{roles: [], permissions: MapSet.new()}}
      }

      assert PermitEx.Absinthe.RequireRole.call(allowed, "admin").errors == []
      assert PermitEx.Absinthe.RequireRole.call(denied, "admin").errors != []
    end

    test "RequireAuthorization supports any_permissions" do
      scope = %{permissions: MapSet.new(["orders:view"]), roles: []}
      resolution = %Absinthe.Resolution{context: %{current_scope: scope}}

      result =
        PermitEx.Absinthe.RequireAuthorization.call(resolution,
          any_permissions: ["orders:view", "orders:manage"]
        )

      assert result.errors == []
    end

    test "RequireAuthorization supports custom error message" do
      scope = %{permissions: MapSet.new(), roles: []}
      resolution = %Absinthe.Resolution{context: %{current_scope: scope}}

      result =
        PermitEx.Absinthe.RequireAuthorization.call(resolution,
          permission: "orders:manage",
          message: "access denied"
        )

      assert Enum.any?(result.errors, &(to_string(&1) =~ "access denied"))
    end

    test "RequireAuthorization supports custom assign_key" do
      scope = %{permissions: MapSet.new(["orders:manage"]), roles: []}
      resolution = %Absinthe.Resolution{context: %{auth: scope}}

      result =
        PermitEx.Absinthe.RequireAuthorization.call(resolution,
          permission: "orders:manage",
          assign_key: :auth
        )

      assert result.errors == []
    end
  end
end
