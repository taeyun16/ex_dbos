defmodule ExDbos.ControlTest do
  use ExUnit.Case, async: true

  alias ExDbos.Client
  alias ExDbos.Control

  defmodule RepoStub do
    @moduledoc false
  end

  defmodule CompatFake do
    @moduledoc false
    def health(client), do: invoke(:health, [client])
    def cancel_workflow(client, workflow_id), do: invoke(:cancel_workflow, [client, workflow_id])
    def resume_workflow(client, workflow_id), do: invoke(:resume_workflow, [client, workflow_id])

    def fork_workflow(client, workflow_id, start_step, params),
      do: invoke(:fork_workflow, [client, workflow_id, start_step, params])

    defp invoke(fun, args) do
      handler = Process.get({__MODULE__, fun}) || raise "missing handler for #{fun}"
      apply(handler, args)
    end
  end

  defmodule IdempotencyFake do
    @moduledoc false
    def with_idempotency(client, action, workflow_id, request_key, opts, operation) do
      handler =
        Process.get({__MODULE__, :with_idempotency}) ||
          raise "missing handler for with_idempotency"

      handler.(client, action, workflow_id, request_key, opts, operation)
    end
  end

  setup do
    client =
      Client.new(
        repo: RepoStub,
        compat_module: CompatFake,
        idempotency_module: IdempotencyFake
      )

    {:ok, client: client}
  end

  test "health/1 returns ok payload on healthy db", %{client: client} do
    Process.put({CompatFake, :health}, fn ^client -> :ok end)

    assert {:ok, %{"status" => "ok"}} = Control.health(client)
  end

  test "health/1 normalizes postgres-shaped errors", %{client: client} do
    Process.put({CompatFake, :health}, fn ^client -> {:error, %{postgres: :db_down}} end)

    assert {:error, %{status: 500, body: %{"error" => message}}} = Control.health(client)
    assert message =~ "postgres"
  end

  test "health/1 preserves normalized errors", %{client: client} do
    expected = %{status: 418, body: %{"error" => "teapot"}}
    Process.put({CompatFake, :health}, fn ^client -> {:error, expected} end)

    assert {:error, ^expected} = Control.health(client)
  end

  test "cancel_workflow/4 routes through idempotency and compat layer", %{client: client} do
    Process.put({IdempotencyFake, :with_idempotency}, fn ^client, "cancel", "wf-1", "req-1", opts, operation ->
      send(self(), {:idempotency_opts, opts})
      operation.()
    end)

    Process.put({CompatFake, :cancel_workflow}, fn ^client, "wf-1" -> {:ok, %{"ok" => true}} end)

    assert {:ok, %{"ok" => true}} =
             Control.cancel_workflow(client, "wf-1", "req-1", ttl_days: 3)

    assert_received {:idempotency_opts, [ttl_days: 3]}
  end

  test "fork_workflow/5 normalizes start_step and params", %{client: client} do
    Process.put({IdempotencyFake, :with_idempotency}, fn ^client, "fork", "wf-1", "req-2", [], operation ->
      operation.()
    end)

    Process.put({CompatFake, :fork_workflow}, fn ^client, "wf-1", start_step, params ->
      send(self(), {:fork_args, start_step, params})
      {:ok, %{"ok" => true, "workflow_id" => "wf-2"}}
    end)

    assert {:ok, %{"ok" => true, "workflow_id" => "wf-2"}} =
             Control.fork_workflow(
               client,
               "wf-1",
               %{start_step: "2", new_workflow_id: "wf-2", ignored: "drop-me"},
               "req-2"
             )

    assert_received {:fork_args, 2, %{"new_workflow_id" => "wf-2"}}
  end

  test "fork_workflow/5 defaults invalid start_step to 0", %{client: client} do
    Process.put({IdempotencyFake, :with_idempotency}, fn ^client, "fork", "wf-1", "req-3", [], operation ->
      operation.()
    end)

    Process.put({CompatFake, :fork_workflow}, fn ^client, "wf-1", start_step, params ->
      send(self(), {:fork_start_step, start_step, params})
      {:ok, %{"ok" => true}}
    end)

    assert {:ok, %{"ok" => true}} =
             Control.fork_workflow(
               client,
               "wf-1",
               %{"start_step" => "invalid", "application_version" => "v2"},
               "req-3"
             )

    assert_received {:fork_start_step, 0, %{"application_version" => "v2"}}
  end

  test "mutation operations normalize non-map success payloads", %{client: client} do
    Process.put({IdempotencyFake, :with_idempotency}, fn _client,
                                                         _action,
                                                         _workflow_id,
                                                         _request_key,
                                                         _opts,
                                                         _operation ->
      {:ok, :done}
    end)

    assert {:ok, %{"result" => :done}} = Control.cancel_workflow(client, "wf-1", "req-4")
  end

  test "mutation operations normalize postgres-shaped errors", %{client: client} do
    Process.put({IdempotencyFake, :with_idempotency}, fn _client,
                                                         _action,
                                                         _workflow_id,
                                                         _request_key,
                                                         _opts,
                                                         _operation ->
      {:error, %{postgres: :write_failure}}
    end)

    assert {:error, %{status: 500, body: %{"error" => message}}} =
             Control.resume_workflow(client, "wf-1", "req-5")

    assert message =~ "postgres"
  end

  test "mutation operations preserve normalized errors", %{client: client} do
    expected = %{status: 409, body: %{"error" => "conflict"}}

    Process.put({IdempotencyFake, :with_idempotency}, fn _client,
                                                         _action,
                                                         _workflow_id,
                                                         _request_key,
                                                         _opts,
                                                         _operation ->
      {:error, expected}
    end)

    assert {:error, ^expected} = Control.resume_workflow(client, "wf-1", "req-6")
  end
end
