# ex_dbos

DBOS control operations for Elixir, with built-in idempotency semantics for mutation endpoints.

[![GitHub Stars](https://img.shields.io/github/stars/taeyun16/ex_dbos?style=flat-square)](https://github.com/taeyun16/ex_dbos/stargazers)
[![GitHub Forks](https://img.shields.io/github/forks/taeyun16/ex_dbos?style=flat-square)](https://github.com/taeyun16/ex_dbos/network/members)
[![GitHub Issues](https://img.shields.io/github/issues/taeyun16/ex_dbos?style=flat-square)](https://github.com/taeyun16/ex_dbos/issues)
[![Top Language](https://img.shields.io/github/languages/top/taeyun16/ex_dbos?style=flat-square)](https://github.com/taeyun16/ex_dbos)
[![Last Commit](https://img.shields.io/github/last-commit/taeyun16/ex_dbos?style=flat-square)](https://github.com/taeyun16/ex_dbos/commits/main)
[![Elixir](https://img.shields.io/badge/Elixir-%7E%3E%201.19-4B275F?style=flat-square&logo=elixir)](https://elixir-lang.org/)
[![DBOS](https://img.shields.io/badge/DBOS-2.11.x-0A7E7E?style=flat-square)](https://www.dbos.dev/)
[![Docs](https://img.shields.io/badge/docs-guides-blue?style=flat-square)](docs/README.md)

## Why ex_dbos

- Provides a small control API surface for DBOS workflows in Elixir.
- Works with DBOS `2.11.x` system schema expectations.
- Adds request-level idempotency for mutation operations with replay support.
- Includes a migration installer for idempotency storage.

## Feature Highlights

- Health check: `ExDbos.Control.health/1`
- Mutation controls:
  - `ExDbos.Control.cancel_workflow/4`
  - `ExDbos.Control.resume_workflow/4`
  - `ExDbos.Control.fork_workflow/5`
- Idempotency reservation/replay for mutation endpoints
- Periodic TTL cleanup for idempotency records

## Installation

Add the dependency:

```elixir
def deps do
  [
    {:ex_dbos, git: "https://github.com/taeyun16/ex_dbos.git", tag: "v0.1.0"}
  ]
end
```

`ex_dbos` does not install DBOS runtime components for you.
It assumes DBOS system schema/tables already exist in the target database.

## DBOS Standard Installation (Official Runtimes)

As of February 7, 2026, DBOS "launch/init" workflows are officially documented for:
Python, TypeScript, Go, and Java.

If you run DBOS workers in one of those runtimes and control them from Elixir via `ex_dbos`,
the standard setup is:

1. Install the runtime SDK in the worker service.
2. Configure system database access (typically PostgreSQL).
3. Add DBOS launch/init code in the worker service startup path.
4. Ensure DBOS system schema/tables are created before production rollout.

Runtime-specific entry points:

- Python
  - Install: `pip install dbos`
  - Follow "Integrating DBOS" guide: [Python guide](https://docs.dbos.dev/python/integrating-dbos)
- TypeScript
  - Install SDK: `npm install @dbos-inc/dbos-sdk@latest`
  - Install CLI: `npm install -g @dbos-inc/dbos-cloud@latest`
  - Schema/setup docs: [TypeScript guide](https://docs.dbos.dev/typescript/integrating-dbos)
  - CLI reference (`dbos schema`): [TypeScript CLI](https://docs.dbos.dev/typescript/reference/cli)
- Go
  - Install SDK: `go get github.com/dbos-inc/dbos-transact-golang`
  - Integrating guide: [Go guide](https://docs.dbos.dev/golang/integrating-dbos)
- Java
  - Add `dev.dbos:transact` dependency in Gradle or Maven
  - Integrating guide: [Java guide](https://docs.dbos.dev/java/integrating-dbos)

General DBOS quickstart index: [DBOS Quickstart](https://docs.dbos.dev/quickstart)

### TypeScript Launch/Init Example (Official Pattern)

The official "Add DBOS To Your App" flow for TypeScript is:

1. Register workflows.
2. Configure DBOS with `DBOS.setConfig`.
3. Launch DBOS with `DBOS.launch`.
4. Start your app server/workers.

```ts
import { DBOS } from "@dbos-inc/dbos-sdk";

async function stepOne() {
  DBOS.logger.info("step one");
}

async function workflowFunction() {
  await DBOS.runStep(() => stepOne(), { name: "stepOne" });
}

const workflow = DBOS.registerWorkflow(workflowFunction);

async function main() {
  DBOS.setConfig({
    name: "my-dbos-worker",
    systemDatabaseUrl: process.env.DBOS_SYSTEM_DATABASE_URL
  });

  await DBOS.launch();
  await workflow();
}
```

## Quickstart

Install the migration template, then migrate:

```bash
mix ex_dbos.install
mix ecto.migrate
```

Create a client and execute control operations:

```elixir
client =
  ExDbos.Client.new(
    repo: MyApp.Repo,
    system_schema: "dbos",
    idempotency_schema: "public",
    idempotency_table: "control_api_idempotency"
  )

:ok = ExDbos.bootstrap(client)

{:ok, %{"status" => "ok"}} = ExDbos.Control.health(client)

{:ok, payload} =
  ExDbos.Control.cancel_workflow(
    client,
    "workflow-123",
    "req-20260206-1",
    ttl_days: 7,
    cleanup_interval_seconds: 300
  )

# payload includes idempotency metadata
_replayed? = payload["idempotency_replayed"]
```

## Docker Compose Workflow Example

This repository includes a ready-to-run local workflow example with:

- PostgreSQL system database
- TypeScript DBOS worker (`DBOS.setConfig` + `DBOS.launch`)
- Elixir smoke check using `ex_dbos`

Run:

```bash
docker compose up -d db dbos-worker
docker compose --profile check run --rm exdbos-check
```

Guide: [`docs/docker-compose-workflow.md`](docs/docker-compose-workflow.md)

## Bootstrap Preflight (Elixir)

Use bootstrap checks during application startup to fail fast when DBOS prerequisites are missing:

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

Default checks:

- DB connection health (`SELECT 1`)
- DBOS system tables in `system_schema`
- idempotency table in `idempotency_schema`

Optional flags:

- `check_idempotency_table: false` to skip idempotency table existence check
- `required_system_tables: [...]` to override the expected DBOS system table set

## API Snapshot

| Function | Purpose | Idempotency |
| --- | --- | --- |
| `health(client)` | Validate DB connectivity (`SELECT 1`) | Not used |
| `cancel_workflow(client, workflow_id, request_key, opts)` | Mark workflow as cancelled when non-terminal | `request_key` required |
| `resume_workflow(client, workflow_id, request_key, opts)` | Re-enqueue workflow when non-terminal | `request_key` required |
| `fork_workflow(client, workflow_id, params, request_key, opts)` | Create a forked workflow and optionally copy historical state | `request_key` required |

## Idempotency Behavior

Mutation endpoints (`cancel`, `resume`, `fork`) use idempotency with this model:

- New request key: operation executes and response is stored.
- Replayed request key (same action/workflow): stored success payload is returned.
- Reused key with different action/workflow: returns conflict (`409`).
- Replayed key whose previous request failed: returns conflict (`409`) with failure context.

Useful options:

- `ttl_days` (default `7`): expiration window for idempotency rows.
- `cleanup_interval_seconds` (default `300`): cleanup throttle interval per table.

## Documentation

- Docs index: [`docs/README.md`](docs/README.md)
- Bootstrap guide: [`docs/bootstrap.md`](docs/bootstrap.md)
- Quickstart: [`docs/quickstart.md`](docs/quickstart.md)
- Docker Compose workflow: [`docs/docker-compose-workflow.md`](docs/docker-compose-workflow.md)
- Control API details: [`docs/control-api.md`](docs/control-api.md)
- Idempotency details: [`docs/idempotency.md`](docs/idempotency.md)
- Troubleshooting: [`docs/troubleshooting.md`](docs/troubleshooting.md)

## License

[MIT](LICENSE)
