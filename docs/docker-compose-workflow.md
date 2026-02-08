# Docker Compose Workflow

This guide runs a local, end-to-end sample with:

- PostgreSQL (`db`)
- DBOS TypeScript worker (`dbos-worker`)
- Elixir `ex_dbos` smoke check (`exdbos-check`)

The compose example uses the official DBOS TypeScript launch pattern:

- install SDK dependency (`@dbos-inc/dbos-sdk`)
- configure with `DBOS.setConfig`
- call `DBOS.launch` at startup

## Files

- Compose file: [`../docker-compose.yml`](../docker-compose.yml)
- DBOS worker example: [`../examples/dbos-worker/main.mjs`](../examples/dbos-worker/main.mjs)
- Elixir smoke script: [`../examples/ex_dbos_compose_smoke.exs`](../examples/ex_dbos_compose_smoke.exs)

## 1) Start Database + DBOS Worker

```bash
docker compose up -d db dbos-worker
```

What this does:

- starts PostgreSQL (`dbos_example`)
- starts a TypeScript worker that launches DBOS against the same database
- optionally runs one sample DBOS workflow (`DBOS_RUN_SAMPLE_WORKFLOW=1`)

## 2) Run ex_dbos Smoke Check

```bash
docker compose --profile check run --rm exdbos-check
```

Smoke check steps:

1. waits for DBOS system tables via `ExDbos.bootstrap(client, check_idempotency_table: false)`
2. ensures `public.control_api_idempotency` exists
3. runs `ExDbos.bootstrap!/1`
4. verifies `ExDbos.Control.health/1`
5. verifies idempotent replay behavior with `cancel_workflow/4`

If successful, script output ends with:

- `ex_dbos compose smoke check completed successfully`

## 3) Stop and Clean Up

```bash
docker compose down -v
```

## Notes

- This workflow is for local verification and examples.
- In production, run DBOS workers in your official runtime service and run `ex_dbos` from your Elixir service against the same system database.
- You can change schema via `DBOS_SYSTEM_SCHEMA` and client options if your environment differs from defaults.
