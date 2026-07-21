# Changelog

## 0.3.0

Additive release. No breaking changes when defaults stay off.

### Added

- Check helpers: `can_any?/2`, `can_all?/2`, `has_any_role?/2`, `has_all_roles?/2`,
  `authorize_role/2`, and `authorize/4` with resource policies.
- Incremental role permissions: `give_permission/3`, `give_permissions/3`,
  `revoke_permission/3`, `revoke_permissions/3`.
- Admin helpers: `get_permission/2`, `get_role_by_id/2`, `update_permission/3`,
  `update_role/3`, `users_with_permission/3`.
- Locked role enforcement (`{:error, :role_locked}`) with `force?: true` escape hatch.
- Optional ETS scope cache (`cache: true`, `cache_ttl`) with automatic invalidation
  and `invalidate_cache/2`, `invalidate_cache_all/0`.
- Telemetry events: `[:permit_ex, :scope, :load]`, `[:permit_ex, :authorize, :stop]`,
  `[:permit_ex, :mutation, :stop]`.
- Optional wildcards (`wildcards: true`) for `orders:*` and `*`.
- Optional super roles (`super_roles: ["super_admin"]`).
- `seed!/2` accepts `context_id:` for context roles.
- `Scope.reload/2`, `Scope.put_assign/3`.
- Policy callbacks receive the full `opts` keyword list.
- HEEx component `PermitEx.Components.permit_can/1` (when Phoenix.Component is available).
- Install task `--id-type uuid|id` for `user_id` / `context_id` column types.
- Configurable schema id types via `user_id_type` / `context_id_type` compile env.

### Changed

- Elixir requirement relaxed to `~> 1.15`.
- Permission name validation allows `*` in the action segment (`orders:*`).
- Documentation aligned with current version and Plug keyword syntax.

### Notes

- Direct user permissions are intentionally not supported; users always get
  permissions through roles.

## 0.1.0

Initial public release.

### Added

- Ecto schemas for permissions, roles, role permissions, and user roles.
- Install task for copying migrations into host applications.
- Global roles for apps without tenants or workspaces.
- Optional context-specific roles for tenants, workspaces, organizations,
  projects, or accounts.
- Role and permission sync APIs.
- Permission and role checks for map/struct scopes.
- Optional Plug guards for controllers and JSON APIs.
- Optional LiveView `on_mount` guards.
- Context role cloning from global templates.
- Documentation for Phoenix, API, and `use_nexus` migration.
- PostgreSQL-backed integration tests and CI workflow.
- Administrative lookup/listing APIs.
- Optional resource policy hook.
