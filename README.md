# ex_dbos

DBOS control SDK for Elixir (`2.11.x` system schema compatible).

## Features

- `health/1`
- `cancel_workflow/4`
- `resume_workflow/4`
- `fork_workflow/5`
- Idempotency reservation/replay semantics
- TTL cleanup for idempotency records

## Installation (git dependency first)

```elixir
def deps do
  [
    {:ex_dbos, git: "https://github.com/dbos-inc/ex_dbos.git", tag: "v0.1.0"}
  ]
end
```

## Setup

Install migration template in your consumer project:

```bash
mix ex_dbos.install
mix ecto.migrate
```

## Usage

```elixir
client =
  ExDbos.Client.new(
    repo: MyApp.Repo,
    system_schema: "dbos",
    idempotency_schema: "public",
    idempotency_table: "control_api_idempotency"
  )

{:ok, _} = ExDbos.Control.health(client)

{:ok, payload} =
  ExDbos.Control.cancel_workflow(
    client,
    "workflow-id",
    "request-idempotency-key",
    ttl_days: 7,
    cleanup_interval_seconds: 300
  )
```
