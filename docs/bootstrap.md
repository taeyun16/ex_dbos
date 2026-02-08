# Bootstrap Preflight

`ex_dbos` provides startup checks via `ExDbos.bootstrap/2` and `ExDbos.bootstrap!/2`.

These checks are read-only and intended for app startup validation.

## Why Bootstrap Checks

`ex_dbos` is a control SDK, not a DBOS runtime launcher.
Your DBOS runtime (Python/TypeScript/Go/Java services) must already be installed and running.

Bootstrap checks help detect:

- wrong database connectivity
- missing DBOS system tables
- missing idempotency table

before control operations are attempted.

## Usage

```elixir
client =
  ExDbos.Client.new(
    repo: MyApp.Repo,
    system_schema: "dbos",
    idempotency_schema: "public",
    idempotency_table: "control_api_idempotency"
  )

:ok = ExDbos.bootstrap!(client)
```

If a check fails:

- `ExDbos.bootstrap/2` returns `{:error, %{check: ..., message: ..., details: ...}}`
- `ExDbos.bootstrap!/2` raises `RuntimeError`

## Check Set

By default bootstrap verifies:

1. Health probe: `SELECT 1`
2. System tables in `system_schema`:
   - `workflow_status`
   - `operation_outputs`
   - `workflow_events`
   - `workflow_events_history`
   - `streams`
3. Idempotency table in `idempotency_schema`

## Options

- `check_idempotency_table: false`
  - Skip idempotency table existence check.
- `required_system_tables: ["..."]`
  - Override expected DBOS system table names.

## Startup Pattern

For fail-fast startup:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo
  ]

  {:ok, supervisor} =
    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)

  client = ExDbos.Client.new(repo: MyApp.Repo)

  case ExDbos.bootstrap(client) do
    :ok ->
      {:ok, supervisor}

    {:error, reason} ->
      Supervisor.stop(supervisor)
      {:error, {:bootstrap_failed, reason}}
  end
end
```

If you prefer soft failure behavior, call `ExDbos.bootstrap/2` and log/telemetry-handle errors.
