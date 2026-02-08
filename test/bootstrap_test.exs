defmodule ExDbos.BootstrapTest do
  use ExUnit.Case, async: true

  alias ExDbos.Bootstrap
  alias ExDbos.Client

  defmodule RepoStub do
    @moduledoc false
  end

  defmodule SQLFake do
    @moduledoc false
    def query(repo, sql, params) do
      handler = Process.get({__MODULE__, :query}) || raise "missing query handler"
      handler.(repo, String.trim(sql), params)
    end
  end

  setup do
    client =
      Client.new(
        repo: RepoStub,
        sql_module: SQLFake,
        system_schema: "dbos",
        idempotency_schema: "public",
        idempotency_table: "control_api_idempotency"
      )

    {:ok, client: client}
  end

  test "run/2 succeeds when all checks pass", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        sql == "SELECT 1" and params == [] ->
          {:ok, %{rows: [[1]]}}

        String.starts_with?(sql, "SELECT table_name") ->
          [schema, expected] = params
          assert schema == "dbos"
          {:ok, %{rows: Enum.map(expected, &[&1])}}

        String.starts_with?(sql, "SELECT 1\nFROM information_schema.tables") and
            params == ["public", "control_api_idempotency"] ->
          {:ok, %{rows: [[1]]}}

        true ->
          flunk("unexpected SQL call: #{sql} #{inspect(params)}")
      end
    end)

    assert :ok = Bootstrap.run(client)
  end

  test "run/2 returns health error when probe fails", %{client: client} do
    put_query_handler(fn _repo, "SELECT 1", [] -> {:error, :db_down} end)

    assert {:error, %{check: :health, reason: :db_down}} = Bootstrap.run(client)
  end

  test "run/2 reports missing system tables", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        sql == "SELECT 1" and params == [] ->
          {:ok, %{rows: [[1]]}}

        String.starts_with?(sql, "SELECT table_name") ->
          {:ok, %{rows: [["workflow_status"], ["operation_outputs"]]}}

        true ->
          flunk("unexpected SQL call: #{sql} #{inspect(params)}")
      end
    end)

    assert {:error,
            %{
              check: :system_tables,
              details: %{missing_tables: missing}
            }} = Bootstrap.run(client)

    assert "streams" in missing
    assert "workflow_events" in missing
  end

  test "run/2 reports missing idempotency table", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        sql == "SELECT 1" and params == [] ->
          {:ok, %{rows: [[1]]}}

        String.starts_with?(sql, "SELECT table_name") ->
          [_, expected] = params
          {:ok, %{rows: Enum.map(expected, &[&1])}}

        String.starts_with?(sql, "SELECT 1\nFROM information_schema.tables") ->
          {:ok, %{rows: []}}

        true ->
          flunk("unexpected SQL call: #{sql} #{inspect(params)}")
      end
    end)

    assert {:error,
            %{
              check: :idempotency_table,
              details: %{
                idempotency_schema: "public",
                idempotency_table: "control_api_idempotency"
              }
            }} = Bootstrap.run(client)
  end

  test "run/2 can skip idempotency table check", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        sql == "SELECT 1" and params == [] ->
          {:ok, %{rows: [[1]]}}

        String.starts_with?(sql, "SELECT table_name") ->
          [_, expected] = params
          {:ok, %{rows: Enum.map(expected, &[&1])}}

        true ->
          flunk("unexpected SQL call: #{sql} #{inspect(params)}")
      end
    end)

    assert :ok = Bootstrap.run(client, check_idempotency_table: false)
  end

  test "run!/2 raises on check failures", %{client: client} do
    put_query_handler(fn _repo, "SELECT 1", [] -> {:error, :network_issue} end)

    assert_raise RuntimeError, ~r/bootstrap failed \(health\)/, fn ->
      Bootstrap.run!(client)
    end
  end

  defp put_query_handler(fun), do: Process.put({SQLFake, :query}, fun)
end
