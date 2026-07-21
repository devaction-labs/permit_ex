# Testing

PermitEx runs integration tests against PostgreSQL because the migrations
use PostgreSQL partial indexes for global and context-specific assignments.

## Local PostgreSQL Container

Start PostgreSQL:

```bash
docker compose up -d postgres
```

Run the test suite:

```bash
DATABASE_URL=postgres://postgres:postgres@localhost:55432/permit_ex_test mix test
```

Stop the container:

```bash
docker compose down
```

## Optional features in tests

Cache, wildcards, and super roles are controlled by application env and are
safe to toggle per-test:

```elixir
setup do
  previous = Application.get_env(:permit_ex, :cache)
  Application.put_env(:permit_ex, :cache, true)
  on_exit(fn -> Application.put_env(:permit_ex, :cache, previous) end)
  :ok
end
```

## GitHub Actions

The repository includes a GitHub Actions workflow with a PostgreSQL service
container. It runs:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
MIX_ENV=dev mix docs
mix hex.build
```

This gives the SDK a real database verification path without requiring a
runtime dependency on a testcontainers library.
