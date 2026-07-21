# Phoenix Guide

This guide shows how to use PermitEx with Phoenix controllers and LiveView.

## Configure the Repo

```elixir
config :permit_ex, repo: MyApp.Repo
```

Optional production features (all off by default):

```elixir
config :permit_ex,
  cache: true,
  cache_ttl: :timer.minutes(5),
  wildcards: true,
  super_roles: ["super_admin"]
```

## Load Permission Data into Your Scope

PermitEx does not replace your authentication system. Use `phx.gen.auth`,
Guardian, Pow, OAuth, or your existing session flow to identify the current
user. After authentication, load roles and permissions into your app scope.

For an app without tenants or workspaces:

```elixir
scope = PermitEx.Scope.for_user(user)
```

For a SaaS app:

```elixir
scope = PermitEx.Scope.for_user(user, workspace)
```

To enrich your own scope struct:

```elixir
%MyApp.Accounts.Scope{user: user, workspace: workspace}
|> PermitEx.Scope.put_permission_data(user, workspace)
```

Your scope must be assigned to `:current_scope` by default:

```elixir
assign(conn, :current_scope, scope)
```

## Controllers

Require one permission:

```elixir
plug PermitEx.Plug.RequirePermission, "orders:manage"
```

Require one role:

```elixir
plug PermitEx.Plug.RequireRole, "admin"
```

Use the general guard for richer checks:

```elixir
plug PermitEx.Plug.RequireAuthorization,
  any_permissions: ["orders:manage", "settings:manage"],
  role: "admin"
```

If your scope is stored under another assign, use the keyword form:

```elixir
plug PermitEx.Plug.RequirePermission,
  permission: "orders:manage",
  assign_key: :auth_scope
```

## LiveView

Add guards to a `live_session`:

```elixir
live_session :app,
  on_mount: [
    {MyAppWeb.UserAuth, :require_authenticated},
    {PermitEx.LiveView.RequirePermission, "orders:view"}
  ] do
  live "/orders", OrderLive.Index, :index
end
```

Use `RequireAuthorization` for redirects and flash messages:

```elixir
{PermitEx.LiveView.RequireAuthorization,
 permission: "settings:manage",
 redirect_to: "/app",
 flash: {:error, "You cannot access that page."}}
```

After changing roles in a long-lived LiveView:

```elixir
scope = PermitEx.Scope.reload(socket.assigns.current_scope)
{:noreply, assign(socket, :current_scope, scope)}
```

## Templates (HEEx)

```elixir
import PermitEx.Components

<.permit_can scope={@current_scope} permission="orders:manage">
  <.link navigate={~p"/orders/new"}>New order</.link>
</.permit_can>
```

Or check inline:

```elixir
<%= if PermitEx.can?(@current_scope, "orders:manage") do %>
  ...
<% end %>
```

## Event Handlers

Route guards protect page access. For mutations, check again inside event
handlers:

```elixir
def handle_event("delete", %{"id" => id}, socket) do
  with :ok <- PermitEx.authorize(socket.assigns.current_scope, "orders:manage") do
    # delete order
    {:noreply, socket}
  else
    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Not allowed.")}
  end
end
```

## Notes

- PermitEx is authorization, not authentication.
- Users receive permissions **only through roles** (no direct user permissions).
- Use contexts only when your app needs scoped roles.
- For long-lived LiveViews, reload the scope after changing a user's roles.
