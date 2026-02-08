defmodule ExDbos.Compat.V2_11Test do
  use ExUnit.Case, async: true

  alias ExDbos.Client
  alias ExDbos.Compat.V2_11

  defmodule RepoStub do
    @moduledoc false
    def transaction(fun), do: {:ok, fun.()}
  end

  defmodule SQLFake do
    @moduledoc false
    def query(repo, sql, params) do
      handler = Process.get({__MODULE__, :query}) || raise "missing query handler"
      handler.(repo, String.trim(sql), params)
    end
  end

  setup do
    {:ok, client: Client.new(repo: RepoStub, sql_module: SQLFake)}
  end

  test "health/1 returns :ok on successful probe", %{client: client} do
    put_query_handler(fn _repo, "SELECT 1", [] -> {:ok, %{rows: [[1]]}} end)

    assert :ok = V2_11.health(client)
  end

  test "health/1 returns error tuple on failed probe", %{client: client} do
    put_query_handler(fn _repo, "SELECT 1", [] -> {:error, :db_down} end)

    assert {:error, :db_down} = V2_11.health(client)
  end

  test "cancel_workflow/2 is no-op when workflow is missing", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      if String.starts_with?(sql, "SELECT status FROM") and params == ["wf-missing"] do
        {:ok, %{rows: []}}
      else
        flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true}} = V2_11.cancel_workflow(client, "wf-missing")
  end

  test "cancel_workflow/2 is no-op when workflow is terminal", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      if String.starts_with?(sql, "SELECT status FROM") and params == ["wf-terminal"] do
        {:ok, %{rows: [["SUCCESS"]], columns: ["status"]}}
      else
        flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true}} = V2_11.cancel_workflow(client, "wf-terminal")
  end

  test "cancel_workflow/2 updates non-terminal workflow", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        String.starts_with?(sql, "SELECT status FROM") and params == ["wf-active"] ->
          {:ok, %{rows: [["RUNNING"]]}}

        String.starts_with?(sql, "UPDATE") and params == ["wf-active"] ->
          assert String.contains?(sql, "SET status = 'CANCELLED'")
          {:ok, %{num_rows: 1}}

        true ->
          flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true}} = V2_11.cancel_workflow(client, "wf-active")
  end

  test "resume_workflow/2 is no-op when workflow is missing", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        sql == "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ" and params == [] ->
          {:ok, %{}}

        String.starts_with?(sql, "SELECT status FROM") and params == ["wf-missing"] ->
          {:ok, %{rows: []}}

        true ->
          flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true}} = V2_11.resume_workflow(client, "wf-missing")
  end

  test "resume_workflow/2 updates non-terminal workflow", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        sql == "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ" and params == [] ->
          {:ok, %{}}

        String.starts_with?(sql, "SELECT status FROM") and params == ["wf-active"] ->
          {:ok, %{rows: [["PENDING"]]}}

        String.starts_with?(sql, "UPDATE") ->
          assert params == ["wf-active", "_dbos_internal_queue"]
          assert String.contains?(sql, "SET status = 'ENQUEUED'")
          {:ok, %{num_rows: 1}}

        true ->
          flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true}} = V2_11.resume_workflow(client, "wf-active")
  end

  test "fork_workflow/4 returns 404 when source workflow is missing", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      if String.starts_with?(sql, "SELECT name, class_name, config_name") and
           params == ["wf-missing"] do
        {:ok, %{rows: []}}
      else
        flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:error, %{status: 404, body: %{"error" => "Workflow not found"}}} =
             V2_11.fork_workflow(client, "wf-missing", 1, %{})
  end

  test "fork_workflow/4 inserts forked workflow when start_step <= 1", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        String.starts_with?(sql, "SELECT name, class_name, config_name") ->
          {:ok,
           %{
             rows: [
               [
                 "name",
                 "class",
                 "config",
                 "v1",
                 "app",
                 "user",
                 ["admin"],
                 "role",
                 %{"k" => "v"}
               ]
             ]
           }}

        String.starts_with?(sql, "INSERT INTO") and String.contains?(sql, "forked_from") ->
          assert params == [
                   "forked-1",
                   "name",
                   "class",
                   "config",
                   "v2",
                   "app",
                   "user",
                   ["admin"],
                   "role",
                   "_dbos_internal_queue",
                   %{"k" => "v"},
                   "wf-source"
                 ]

          {:ok, %{num_rows: 1}}

        true ->
          flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true, "workflow_id" => "forked-1"}} =
             V2_11.fork_workflow(client, "wf-source", 1, %{
               "new_workflow_id" => "forked-1",
               "application_version" => "v2"
             })
  end

  test "fork_workflow/4 copies historical data when start_step > 1", %{client: client} do
    put_query_handler(fn _repo, sql, params ->
      cond do
        String.starts_with?(sql, "SELECT name, class_name, config_name") ->
          {:ok,
           %{
             rows: [
               [
                 "name",
                 "class",
                 "config",
                 "v1",
                 "app",
                 "user",
                 ["admin"],
                 "role",
                 %{"k" => "v"}
               ]
             ]
           }}

        String.starts_with?(sql, "INSERT INTO") and String.contains?(sql, "forked_from") ->
          {:ok, %{num_rows: 1}}

        String.starts_with?(sql, "INSERT INTO") and String.contains?(sql, "child_workflow_id") ->
          assert params == ["forked-2", "wf-source", 3]
          {:ok, %{num_rows: 2}}

        String.starts_with?(sql, "INSERT INTO") and
          String.contains?(sql, "(workflow_uuid, function_id, key, value)") and
            not String.contains?(sql, "weh1.key") ->
          assert params == ["forked-2", "wf-source", 3]
          {:ok, %{num_rows: 3}}

        String.starts_with?(sql, "INSERT INTO") and String.contains?(sql, "SELECT $1, weh1.key") ->
          assert params == ["forked-2", "wf-source", 3]
          {:ok, %{num_rows: 1}}

        String.starts_with?(sql, "INSERT INTO") and
            String.contains?(sql, "(workflow_uuid, function_id, key, value, offset)") ->
          assert params == ["forked-2", "wf-source", 3]
          {:ok, %{num_rows: 4}}

        true ->
          flunk("unexpected SQL: #{sql} #{inspect(params)}")
      end
    end)

    assert {:ok, %{"ok" => true, "workflow_id" => "forked-2"}} =
             V2_11.fork_workflow(client, "wf-source", 3, %{
               "new_workflow_id" => "forked-2"
             })
  end

  test "fork_workflow/4 raises when insert fails", %{client: client} do
    put_query_handler(fn _repo, sql, _params ->
      cond do
        String.starts_with?(sql, "SELECT name, class_name, config_name") ->
          {:ok,
           %{
             rows: [
               [
                 "name",
                 "class",
                 "config",
                 "v1",
                 "app",
                 "user",
                 ["admin"],
                 "role",
                 %{"k" => "v"}
               ]
             ]
           }}

        String.starts_with?(sql, "INSERT INTO") and String.contains?(sql, "forked_from") ->
          {:error, :insert_failed}

        true ->
          flunk("unexpected SQL: #{sql}")
      end
    end)

    assert_raise RuntimeError, ~r/failed to insert forked workflow/, fn ->
      V2_11.fork_workflow(client, "wf-source", 1, %{"new_workflow_id" => "forked-3"})
    end
  end

  test "fork_workflow/4 returns compat error when source query fails", %{client: client} do
    put_query_handler(fn _repo, sql, _params ->
      if String.starts_with?(sql, "SELECT name, class_name, config_name") do
        {:error, :source_query_failed}
      else
        flunk("unexpected SQL: #{sql}")
      end
    end)

    assert {:error, :source_query_failed} = V2_11.fork_workflow(client, "wf-source", 1, %{})
  end

  defp put_query_handler(fun), do: Process.put({SQLFake, :query}, fun)
end
