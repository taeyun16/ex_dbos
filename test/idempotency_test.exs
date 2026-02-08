defmodule ExDbos.IdempotencyTest do
  use ExUnit.Case, async: true

  alias ExDbos.Client
  alias ExDbos.Idempotency

  defmodule RepoStub do
    @moduledoc false
    def transaction(fun), do: {:ok, fun.()}
  end

  defmodule SQLFake do
    @moduledoc false
    def query(repo, sql, params) do
      handler = Process.get({__MODULE__, :query}) || raise "missing SQL query handler"
      handler.(repo, sql, params)
    end
  end

  setup do
    {:ok, state} =
      Agent.start_link(fn ->
        %{
          rows: %{},
          delete_calls: 0,
          fail_delete: false
        }
      end)

    Process.put({SQLFake, :query}, build_query_mock(state))

    client =
      Client.new(
        repo: RepoStub,
        sql_module: SQLFake,
        idempotency_table: unique_table_name()
      )

    on_exit(fn ->
      if Process.alive?(state) do
        Agent.stop(state)
      end
    end)

    {:ok, client: client, state: state}
  end

  test "rejects non-binary idempotency keys", %{client: client} do
    assert {:error, %{status: 400, body: %{"error" => "Invalid idempotency key"}}} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", 123, [], fn ->
               {:ok, %{"ok" => true}}
             end)
  end

  test "rejects empty idempotency keys", %{client: client} do
    assert {:error, %{status: 400, body: %{"error" => "Idempotency key must not be empty"}}} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "", [], fn ->
               {:ok, %{"ok" => true}}
             end)
  end

  test "rejects whitespace-only idempotency keys", %{client: client} do
    assert {:error, %{status: 400, body: %{"error" => "Idempotency key must not be empty"}}} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "   ", [], fn ->
               {:ok, %{"ok" => true}}
             end)
  end

  test "rejects too-long idempotency keys", %{client: client} do
    long_key = String.duplicate("a", 201)

    assert {:error, %{status: 400, body: %{"error" => "Idempotency key is too long (max 200 chars)"}}} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", long_key, [], fn ->
               {:ok, %{"ok" => true}}
             end)
  end

  test "persists successful result and replays on repeated request key", %{
    client: client,
    state: state
  } do
    assert {:ok,
            %{
              "ok" => true,
              "idempotency_key" => "req-1",
              "idempotency_replayed" => false
            }} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-1", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert {:ok,
            %{
              "ok" => true,
              "idempotency_key" => "req-1",
              "idempotency_replayed" => true
            }} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-1", [], fn ->
               flunk("operation should not execute for replayed key")
             end)

    assert Agent.get(state, & &1.delete_calls) == 1
  end

  test "returns conflict when request key is reused for different action", %{client: client} do
    assert {:ok, _} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-2", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert {:error, %{status: 409, body: %{"error" => message}}} =
             Idempotency.with_idempotency(client, "resume", "wf-1", "req-2", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert message =~ "different action/workflow"
  end

  test "marks failed operations and blocks retries with same key", %{client: client, state: state} do
    failure = String.duplicate("x", 5000)

    assert {:error, ^failure} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-3", [], fn ->
               {:error, failure}
             end)

    row = Agent.get(state, &Map.fetch!(&1.rows, "req-3"))
    assert row.status == "failed"
    assert String.length(row.error_message) == 4000

    assert {:error, %{status: 409, body: %{"error" => message}}} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-3", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert message =~ "Previous request with this idempotency key failed"
  end

  test "returns conflict when matching request key is still in progress", %{
    client: client,
    state: state
  } do
    put_row(state, "req-4", %{
      action: "cancel",
      workflow_id: "wf-1",
      status: "in_progress",
      response_json: nil,
      error_message: nil
    })

    assert {:error, %{status: 409, body: %{"error" => message}}} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-4", [], fn ->
               {:ok, %{"ok" => true}}
             end)

    assert message =~ "still in progress"
  end

  test "cleanup_expired/2 returns SQL error when delete fails", %{client: client, state: state} do
    Agent.update(state, &Map.put(&1, :fail_delete, true))

    assert {:error, :delete_failed} = Idempotency.cleanup_expired(client, ttl_days: 7)
  end

  test "replay decodes nil and map response payloads", %{client: client, state: state} do
    put_row(state, "req-nil", %{
      action: "cancel",
      workflow_id: "wf-1",
      status: "succeeded",
      response_json: nil,
      error_message: nil
    })

    assert {:ok,
            %{
              "idempotency_key" => "req-nil",
              "idempotency_replayed" => true
            }} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-nil", [], fn ->
               flunk("operation should not execute for replayed key")
             end)

    put_row(state, "req-map", %{
      action: "cancel",
      workflow_id: "wf-1",
      status: "succeeded",
      response_json: %{"x" => 1},
      error_message: nil
    })

    assert {:ok,
            %{
              "x" => 1,
              "idempotency_key" => "req-map",
              "idempotency_replayed" => true
            }} =
             Idempotency.with_idempotency(client, "cancel", "wf-1", "req-map", [], fn ->
               flunk("operation should not execute for replayed key")
             end)
  end

  defp build_query_mock(state) do
    fn _repo, sql, params ->
      sql = String.trim(sql)

      cond do
        String.starts_with?(sql, "CREATE TABLE IF NOT EXISTS") ->
          {:ok, %{rows: []}}

        String.starts_with?(sql, "CREATE INDEX IF NOT EXISTS") ->
          {:ok, %{rows: []}}

        String.starts_with?(sql, "DELETE FROM") ->
          Agent.get_and_update(state, fn current ->
            if current.fail_delete do
              {{:error, :delete_failed}, current}
            else
              {{:ok, %{num_rows: 0}}, %{current | delete_calls: current.delete_calls + 1}}
            end
          end)

        String.starts_with?(sql, "INSERT INTO") and
            String.contains?(sql, "ON CONFLICT (request_key) DO NOTHING") ->
          [request_key, action, workflow_id] = params

          Agent.get_and_update(state, fn current ->
            if Map.has_key?(current.rows, request_key) do
              {{:ok, %{rows: []}}, current}
            else
              row = %{
                action: action,
                workflow_id: workflow_id,
                status: "in_progress",
                response_json: nil,
                error_message: nil
              }

              {{:ok, %{rows: [[request_key]]}}, %{current | rows: Map.put(current.rows, request_key, row)}}
            end
          end)

        String.starts_with?(
          sql,
          "SELECT action, workflow_id, status, response_json, error_message"
        ) ->
          [request_key] = params

          Agent.get(state, fn current ->
            case current.rows[request_key] do
              nil ->
                {:ok, %{rows: []}}

              row ->
                {:ok,
                 %{
                   rows: [
                     [
                       row.action,
                       row.workflow_id,
                       row.status,
                       row.response_json,
                       row.error_message
                     ]
                   ]
                 }}
            end
          end)

        String.starts_with?(sql, "UPDATE") and String.contains?(sql, "SET status = 'succeeded'") ->
          [response_json, request_key] = params

          Agent.update(state, fn current ->
            row = Map.fetch!(current.rows, request_key)

            updated = %{
              row
              | status: "succeeded",
                response_json: response_json,
                error_message: nil
            }

            %{current | rows: Map.put(current.rows, request_key, updated)}
          end)

          {:ok, %{num_rows: 1}}

        String.starts_with?(sql, "UPDATE") and String.contains?(sql, "SET status = 'failed'") ->
          [error_message, request_key] = params

          Agent.update(state, fn current ->
            row = Map.fetch!(current.rows, request_key)
            updated = %{row | status: "failed", error_message: error_message}
            %{current | rows: Map.put(current.rows, request_key, updated)}
          end)

          {:ok, %{num_rows: 1}}

        true ->
          raise "unexpected SQL: #{inspect(sql)} params=#{inspect(params)}"
      end
    end
  end

  defp put_row(state, key, row) do
    Agent.update(state, fn current ->
      %{current | rows: Map.put(current.rows, key, row)}
    end)
  end

  defp unique_table_name do
    "control_api_idempotency_#{System.unique_integer([:positive, :monotonic])}"
  end
end
