# Control API

`ExDbos.Control` provides four public operations:

- `health/1`
- `cancel_workflow/4`
- `resume_workflow/4`
- `fork_workflow/5`

All functions return:

- `{:ok, map()}`
- `{:error, term()}`

In practice, errors are normalized into maps like:

```elixir
%{status: integer(), body: map()}
```

## `health/1`

Signature:

```elixir
ExDbos.Control.health(client)
```

Purpose:

- Runs a DB connectivity check (`SELECT 1`) through the configured repo.

Success:

```elixir
{:ok, %{"status" => "ok"}}
```

Notes:

- `health/1` does not use idempotency.

## `cancel_workflow/4`

Signature:

```elixir
ExDbos.Control.cancel_workflow(client, workflow_id, request_key, opts \\ [])
```

Purpose:

- Marks a workflow as cancelled when it is not in terminal state.
- If workflow is missing or already terminal, returns success with no-op semantics.

Parameters:

- `client`: `%ExDbos.Client{}`
- `workflow_id`: DBOS workflow UUID/string
- `request_key`: idempotency key for this request
- `opts`: includes idempotency options (`ttl_days`, `cleanup_interval_seconds`)

Success payload (example):

```elixir
{:ok, %{"ok" => true, "idempotency_key" => "req-1", "idempotency_replayed" => false}}
```

## `resume_workflow/4`

Signature:

```elixir
ExDbos.Control.resume_workflow(client, workflow_id, request_key, opts \\ [])
```

Purpose:

- Re-enqueues workflow execution for non-terminal workflows.
- Resets several runtime fields (queue/deadline/recovery attempt related fields) before enqueue.
- If workflow is missing or terminal, returns success with no-op semantics.

Parameters:

- `client`: `%ExDbos.Client{}`
- `workflow_id`: DBOS workflow UUID/string
- `request_key`: idempotency key for this request
- `opts`: includes idempotency options (`ttl_days`, `cleanup_interval_seconds`)

Success payload (example):

```elixir
{:ok, %{"ok" => true, "idempotency_key" => "req-2", "idempotency_replayed" => false}}
```

## `fork_workflow/5`

Signature:

```elixir
ExDbos.Control.fork_workflow(client, workflow_id, params, request_key, opts \\ [])
```

Purpose:

- Creates a new workflow fork from an existing workflow.
- Optionally copies operation outputs/events/streams depending on `start_step`.

Parameters:

- `client`: `%ExDbos.Client{}`
- `workflow_id`: source workflow identifier
- `params`: map of fork options
- `request_key`: idempotency key for this request
- `opts`: includes idempotency options (`ttl_days`, `cleanup_interval_seconds`)

Supported `params` keys:

- `start_step` (integer or numeric string):
  - Defaults to `0` if missing/invalid.
  - Historical copy runs only when `start_step > 1`.
- `new_workflow_id` (string, optional):
  - If omitted, a UUID is generated.
- `application_version` (string, optional):
  - If omitted, source workflow application version is used.

Success payload (example):

```elixir
{:ok,
 %{
   "ok" => true,
   "workflow_id" => "new-workflow-id",
   "idempotency_key" => "req-3",
   "idempotency_replayed" => false
 }}
```

## Idempotency Notes for Mutation Endpoints

- All mutation endpoints (`cancel`, `resume`, `fork`) require a request key.
- Same key + same action/workflow can replay a previously successful response.
- Same key + different action/workflow returns conflict (`409`).
- If previous attempt with the key failed, subsequent calls return conflict (`409`).

For full details, see [Idempotency](idempotency.md).
