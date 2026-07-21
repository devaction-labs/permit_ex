# PermitEx

Role and permission management for Ecto and Phoenix applications.

PermitEx is a small RBAC toolkit inspired by Laravel Spatie Permission:
permissions live in the database, roles collect permissions, users receive
roles globally or inside an optional context, and your application checks the
current scope.

Users always receive permissions **through roles** — there is no direct
user-permission assignment.

Use it for:

- Ecto applications that need database-backed roles and permissions.
- Phoenix controllers and JSON APIs.
- Phoenix LiveView routes and events.
- Absinthe GraphQL fields.
- SaaS applications with tenants, workspaces, organizations, projects, or accounts.
- Regular applications without tenants.

## Status

`0.3.0` is an additive release over the initial public API. Optional features
(cache, wildcards, super roles) default to **off**, so existing installs keep
the same behaviour until you opt in. The migration remains part of the public
contract — review table names and indexes before installing into an existing
system.

## Concepts

### Permission

A permission is a string such as:

```text
orders:view
orders:manage
settings:manage
```

With `wildcards: true`, roles may also hold `orders:*` or `*`.

PermitEx stores permissions as strings instead of atoms so they can be
seeded, edited in admin screens, and exposed through APIs without creating atoms
at runtime.

### Role

A role groups permissions:

```elixir
PermitEx.seed!(
  permissions: [
    {"orders:view", "View orders"},
    {"orders:manage", "Create, edit, and delete orders"}
  ],
  roles: [
    {"admin", "Administrator", ["orders:view", "orders:manage"]},
    {"viewer", "Read-only user", ["orders:view"]}
  ]
)
```

### Context

Contexts are optional.

In a regular app, assign roles globally:

```elixir
{:ok, role} = PermitEx.upsert_role("admin")
{:ok, _user_role} = PermitEx.assign_role(user.id, role)
```

In a SaaS app, pass your tenant, workspace, organization, project, or account id
as the context:

```elixir
{:ok, role} = PermitEx.upsert_context_role("admin", workspace.id)
{:ok, _user_role} = PermitEx.assign_role(user.id, role, workspace.id)
```

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:permit_ex, "~> 0.3.0"}
  ]
end
```

Configure your repo:

```elixir
config :permit_ex, repo: MyApp.Repo
```

Optional features:

```elixir
config :permit_ex,
  cache: true,
  cache_ttl: :timer.minutes(5),
  wildcards: true,
  super_roles: ["super_admin"]
```

Install and run the migration:

```bash
mix permit_ex.install
# or, for integer user/context ids:
# mix permit_ex.install --id-type id
mix ecto.migrate
```

The installer copies a migration with these tables:

- `permit_ex_permissions`
- `permit_ex_roles`
- `permit_ex_role_permissions`
- `permit_ex_user_roles`

## Quick Start

Seed global permissions and role templates:

```elixir
PermitEx.seed!(
  permissions: [
    {"orders:view", "View orders"},
    {"orders:manage", "Create, edit, and delete orders"},
    {"settings:manage", "Manage settings"}
  ],
  roles: [
    {"admin", "Administrator", ["orders:view", "orders:manage", "settings:manage"]},
    {"viewer", "Read-only user", ["orders:view"]}
  ]
)
```

Assign roles:

```elixir
{:ok, _count} = PermitEx.sync_roles(user.id, ["admin"])
```

Load a scope:

```elixir
scope = PermitEx.Scope.for_user(user)
```

Check permissions and roles:

```elixir
PermitEx.can?(scope, "orders:manage")
PermitEx.can_any?(scope, ["orders:view", "orders:manage"])
PermitEx.has_role?(scope, "admin")
PermitEx.authorize(scope, "settings:manage")
```

## Context-Specific Roles

Clone global role templates into a context:

```elixir
{:ok, roles} = PermitEx.clone_roles_to_context(workspace.id)
```

Or seed directly into a context:

```elixir
PermitEx.seed!(definitions, context_id: workspace.id)
```

Then assign roles inside that context:

```elixir
{:ok, _count} = PermitEx.sync_roles(user.id, ["admin"], workspace.id)
scope = PermitEx.Scope.for_user(user, workspace)
```

When a role name exists globally and inside the context, PermitEx resolves
the context-specific role first.

## Sync and incremental APIs

Replace all permissions for a role:

```elixir
{:ok, _role} =
  PermitEx.sync_permissions(role, [
    "orders:view",
    "orders:manage"
  ])
```

Add or remove permissions without a full replace:

```elixir
{:ok, _count} = PermitEx.give_permission(role, "orders:delete")
{:ok, _count} = PermitEx.revoke_permission(role, "orders:delete")
```

Replace all roles for a user:

```elixir
{:ok, _count} = PermitEx.sync_roles(user.id, ["admin", "billing"], workspace.id)
```

Add or remove roles without replacing the full set:

```elixir
{:ok, _user_role} = PermitEx.assign_role(user.id, "viewer", workspace.id)
{:ok, _count} = PermitEx.assign_roles(user.id, ["viewer", "support"], workspace.id)
{:ok, _count} = PermitEx.revoke_role(user.id, "viewer", workspace.id)
```

By default, sync APIs return an error for missing names:

```elixir
{:error, {:roles_not_found, ["missing_role"]}}
{:error, {:permissions_not_found, ["orders:delete"]}}
```

Pass `allow_missing?: true` only for intentionally partial imports.

Locked roles return `{:error, :role_locked}` on permission/role mutations unless
you pass `force?: true`.

## Phoenix and APIs

PermitEx includes optional Plug, LiveView, and Absinthe adapters. They are
compiled only when the corresponding dependency is available.

For controllers or JSON APIs:

```elixir
plug PermitEx.Plug.RequirePermission, "orders:manage"
plug PermitEx.Plug.RequireRole, "admin"
```

For LiveView:

```elixir
on_mount {PermitEx.LiveView.RequirePermission, "orders:view"}
on_mount {PermitEx.LiveView.RequireRole, "admin"}
```

More examples:

- [Phoenix Guide](docs/phoenix.md)
- [API Guide](docs/api.md)
- [Absinthe Guide](docs/absinthe.md)
- [Testing Guide](docs/testing.md)
- [use_nexus Migration Notes](docs/use-nexus.md)

## Publishing

Before publishing:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix docs
mix hex.build
```

Publish with:

```bash
mix hex.publish
```

## License

MIT. See [LICENSE](LICENSE).
