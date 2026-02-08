# Idempotency

`ex_dbos` applies idempotency to mutation endpoints:

- `cancel_workflow/4`
- `resume_workflow/4`
- `fork_workflow/5`

`health/1` is not idempotency-backed.

## Request Key Validation

The request key must:

- Be a string
- Not be empty after trim
- Be at most 200 bytes

Invalid keys return `{:error, %{status: 400, body: ...}}`.

## Reservation and Replay Flow

Each key is stored with:

- `action`
- `workflow_id`
- `status` (`in_progress`, `succeeded`, `failed`)
- response/error data

High-level behavior:

1. Attempt to reserve the key with status `in_progress`.
2. If reservation succeeds, run the operation.
3. On success, persist response as `succeeded`.
4. On failure, persist error as `failed`.
5. If key already exists:
   - Same action + workflow + `succeeded` => replay stored payload
   - Same action + workflow + `in_progress` => conflict (`409`)
   - Same action + workflow + `failed` => conflict (`409`) with previous failure context
   - Different action/workflow => conflict (`409`)

When replaying a successful call, response includes:

```elixir
"idempotency_replayed" => true
```

When not replayed:

```elixir
"idempotency_replayed" => false
```

## Cleanup and TTL

Idempotency rows are cleaned up by age:

- `ttl_days` (default `7`)
- `cleanup_interval_seconds` (default `300`)

Cleanup query:

- Deletes rows with `updated_at < NOW() - make_interval(days => ttl_days)`.

Cleanup scheduling behavior:

- Cleanup is throttled per idempotency table via ETS state.
- Every mutation call can trigger cleanup, but not more often than `cleanup_interval_seconds`.

## Recommended Client Practices

- Use a stable, unique request key per user intent (not per retry attempt).
- Reuse the same key for retried network/timeout attempts of the same logical request.
- Never reuse a key for a different workflow/action pair.
- Treat `409` idempotency conflicts as deterministic outcomes; inspect the error body and decide whether to retry with a new key or surface to caller.
