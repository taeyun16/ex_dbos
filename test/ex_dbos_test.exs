defmodule ExDbosTest do
  use ExUnit.Case, async: true

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

  test "new_client/1 delegates to ExDbos.Client.new/1" do
    client = ExDbos.new_client(repo: RepoStub)

    assert client.repo == RepoStub
    assert client.system_schema == "dbos"
    assert client.idempotency_schema == "public"
  end

  test "bootstrap/2 delegates to bootstrap module" do
    client = ExDbos.new_client(repo: RepoStub, sql_module: SQLFake)

    Process.put({SQLFake, :query}, fn _repo, sql, params ->
      cond do
        sql == "SELECT 1" and params == [] ->
          {:ok, %{rows: [[1]]}}

        String.starts_with?(sql, "SELECT table_name") ->
          [_, expected] = params
          {:ok, %{rows: Enum.map(expected, &[&1])}}

        true ->
          flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert :ok = ExDbos.bootstrap(client, check_idempotency_table: false)
  end
end
