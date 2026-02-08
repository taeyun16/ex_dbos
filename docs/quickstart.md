# Quickstart

This guide gets you from dependency install to a successful control operation.

## Prerequisites

- Elixir `~> 1.19`
- An Ecto repo module configured for PostgreSQL
- DBOS system schema/tables available (default schema: `"dbos"`)
- DBOS worker runtime installed in an official SDK (Python/TypeScript/Go/Java)

## 1) Add Dependency

```elixir
def deps do
  [
    {:ex_dbos, git: "https://github.com/taeyun16/ex_dbos.git", tag: "v0.1.0"}
  ]
end
```

Then:

```bash
mix deps.get
```

## 2) Install Idempotency Migration

`ex_dbos` ships a Mix task that copies the migration template into your app:

```bash
mix ex_dbos.install
mix ecto.migrate
```

If the migration already exists, the task prints a skip message instead of creating duplicates.

## 3) Build a Client

```elixir
client =
  ExDbos.Client.new(
    repo: MyApp.Repo,
    system_schema: "dbos",
    idempotency_schema: "public",
    idempotency_table: "control_api_idempotency"
  )
```

Required:

- `repo`: your Ecto repo module

Optional (with defaults):

- `system_schema`: `"dbos"`
- `idempotency_schema`: `"public"`
- `idempotency_table`: `"control_api_idempotency"`

## 4) Call Control APIs

Run bootstrap preflight once during startup:

```elixir
:ok = ExDbos.bootstrap!(client)
```

Health check:

```elixir
{:ok, %{"status" => "ok"}} = ExDbos.Control.health(client)
```

Mutation operation with idempotency:

```elixir
{:ok, payload} =
  ExDbos.Control.cancel_workflow(
    client,
    "workflow-123",
    "req-20260206-001",
    ttl_days: 7,
    cleanup_interval_seconds: 300
  )
```

Expected success payload shape (example):

```elixir
%{
  "ok" => true,
  "idempotency_key" => "req-20260206-001",
  "idempotency_replayed" => false
}
```

On replay with the same key/action/workflow, the response includes:

```elixir
"idempotency_replayed" => true
```

## Next

- [Bootstrap Preflight](bootstrap.md)
- [Control API](control-api.md)
- [Idempotency](idempotency.md)
- [Troubleshooting](troubleshooting.md)
