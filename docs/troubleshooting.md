# Troubleshooting

## Invalid Schema or Table Identifiers

Symptoms:

- `ArgumentError` mentioning `invalid schema` or `invalid table`

Cause:

- `ExDbos.SQL.identifier!/2` accepts only SQL-safe identifiers (`[a-zA-Z_][a-zA-Z0-9_]*`).

Fix:

- Use plain schema/table names without quotes, spaces, or punctuation.
- Example valid values:
  - `system_schema: "dbos"`
  - `idempotency_schema: "public"`
  - `idempotency_table: "control_api_idempotency"`

## Missing DBOS System Tables

Symptoms:

- PostgreSQL errors such as `relation ... does not exist` during control calls

Cause:

- DBOS system schema/tables are missing or `system_schema` points to the wrong schema.

Fix:

- Verify DBOS has initialized system tables in the target database.
- Confirm your client uses the correct `system_schema`.
- Verify connection target (database/host) matches your DBOS runtime environment.

Tip:

- Run `ExDbos.bootstrap(client)` and inspect `{:error, %{check: :system_tables, details: ...}}`.

## Idempotency Key Conflicts (`409`)

Symptoms:

- Conflict responses for mutation endpoints

Common causes:

- Same key reused for a different action or workflow
- Prior request with same key still `in_progress`
- Prior request with same key is `failed`

Fix:

- Reuse keys only for retries of the exact same logical request.
- For new logical requests, generate a new key.
- If a previous request failed, resolve root cause and retry with a new key.

## Migration Installation Confusion

Symptoms:

- `mix ex_dbos.install` prints skip message
- Migration file not where expected

Behavior:

- The installer writes to `priv/repo/migrations`.
- If a migration ending with `_create_control_api_idempotency.exs` already exists, it skips creation.

Fix:

- Check `priv/repo/migrations` in your application project.
- Run `mix ecto.migrate` after confirming migration presence.

## Bootstrap Check Failures

Symptoms:

- `ExDbos.bootstrap/2` returns `{:error, ...}`
- `ExDbos.bootstrap!/2` raises on app startup

Typical causes:

- `check: :health`:
  - DB connection/config mismatch
- `check: :system_tables`:
  - DBOS runtime schema not initialized in this database
- `check: :idempotency_table`:
  - migration not applied for `control_api_idempotency`

Fix:

- Verify DB URL and credentials.
- Verify `system_schema` / `idempotency_schema` / `idempotency_table` values.
- Run idempotency migration (`mix ex_dbos.install`, then `mix ecto.migrate`) in your app.

## Quick Diagnostics Checklist

1. Verify dependency fetch/compile:
   - `mix deps.get`
   - `mix compile`
2. Verify DB reachability:
   - `ExDbos.Control.health(client)`
3. Verify idempotency table exists:
   - Check `public.control_api_idempotency` (or your configured table)
4. Verify DBOS schema/table names:
   - `system_schema` should match deployed DBOS system schema
5. Validate request key shape:
   - non-empty string, max 200 bytes
