# Absinthe Guide

PermitEx includes optional Absinthe middleware compiled only when `:absinthe`
is present in the project.

## Setup

Add `:absinthe` to your dependencies and configure PermitEx normally:

```elixir
def deps do
  [
    {:permit_ex, "~> 0.3.0"},
    {:absinthe, "~> 1.10"},
    {:absinthe_plug, "~> 1.5"}
  ]
end
```

```elixir
config :permit_ex, repo: MyApp.Repo
```

## Passing the Scope to Absinthe

Load the authorization scope in your context-building plug and pass it through
Absinthe's context map:

```elixir
defmodule MyAppWeb.Context do
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    scope = conn.assigns[:current_scope]
    Absinthe.Plug.put_options(conn, context: %{current_scope: scope})
  end
end
```

Add it to your router pipeline:

```elixir
pipeline :graphql do
  plug MyAppWeb.AuthPipeline   # sets conn.assigns.current_scope
  plug MyAppWeb.Context
  plug Absinthe.Plug, schema: MyApp.Schema
end
```

## Field-Level Middleware

Require a permission on a single field:

```elixir
middleware PermitEx.Absinthe.RequirePermission, "orders:manage"
```

Require a role:

```elixir
middleware PermitEx.Absinthe.RequireRole, "admin"
```

Use `RequireAuthorization` for richer checks:

```elixir
middleware PermitEx.Absinthe.RequireAuthorization,
  any_permissions: ["orders:manage", "settings:manage"]
```

## Full Example

```elixir
defmodule MyApp.Schema do
  use Absinthe.Schema

  mutation do
    field :create_order, :order do
      middleware PermitEx.Absinthe.RequirePermission, "orders:manage"
      arg :input, non_null(:order_input)
      resolve &MyApp.Resolvers.Orders.create/2
    end

    field :delete_order, :order do
      middleware PermitEx.Absinthe.RequireAuthorization,
        any_roles: ["admin", "support"]
      arg :id, non_null(:id)
      resolve &MyApp.Resolvers.Orders.delete/2
    end
  end

  query do
    field :orders, list_of(:order) do
      middleware PermitEx.Absinthe.RequirePermission, "orders:view"
      resolve &MyApp.Resolvers.Orders.list/2
    end
  end
end
```

## Custom Scope Key

If your context uses a different key:

```elixir
middleware PermitEx.Absinthe.RequireAuthorization,
  permission: "orders:manage",
  assign_key: :auth_scope
```

## Custom Error Message

```elixir
middleware PermitEx.Absinthe.RequireAuthorization,
  permission: "orders:manage",
  message: "You do not have permission to manage orders"
```

## Multi-Tenant SaaS

Load the workspace-scoped scope before passing it to Absinthe:

```elixir
def call(conn, _opts) do
  workspace = conn.assigns[:current_workspace]
  user = conn.assigns[:current_user]
  scope = PermitEx.Scope.for_user(user, workspace)
  Absinthe.Plug.put_options(conn, context: %{current_scope: scope})
end
```

The middleware checks apply the same context-aware role resolution as Plug and
LiveView adapters.
