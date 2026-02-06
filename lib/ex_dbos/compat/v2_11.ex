defmodule ExDbos.Compat.V2_11 do
  @moduledoc """
  DBOS 2.11.x-compatible control SQL operations.
  """

  alias Ecto.Adapters.SQL
  alias ExDbos.Client
  alias ExDbos.SQL, as: ExSql
  alias ExDbos.Schema.System

  @internal_queue "_dbos_internal_queue"
  @terminal_statuses ["SUCCESS", "ERROR"]

  @spec health(Client.t()) :: :ok | {:error, term()}
  def health(%Client{repo: repo}) do
    case SQL.query(repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec cancel_workflow(Client.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def cancel_workflow(client, workflow_id) do
    status_table = System.workflow_status_table(client)

    client.repo.transaction(fn ->
      with {:ok, row} <- fetch_status(client, status_table, workflow_id) do
        if is_nil(row) or row["status"] in @terminal_statuses do
          {:ok, %{"ok" => true}}
        else
          sql = """
          UPDATE #{status_table}
          SET status = 'CANCELLED',
              queue_name = NULL,
              deduplication_id = NULL,
              started_at_epoch_ms = NULL,
              updated_at = #{ExSql.now_epoch_ms_fragment()}
          WHERE workflow_uuid = $1
          """

          case SQL.query(client.repo, sql, [workflow_id]) do
            {:ok, _} -> {:ok, %{"ok" => true}}
            {:error, reason} -> {:error, reason}
          end
        end
      end
    end)
    |> unwrap_tx()
  end

  @spec resume_workflow(Client.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def resume_workflow(client, workflow_id) do
    status_table = System.workflow_status_table(client)

    client.repo.transaction(fn ->
      _ =
        SQL.query(
          client.repo,
          "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ",
          []
        )

      with {:ok, row} <- fetch_status(client, status_table, workflow_id) do
        cond do
          is_nil(row) ->
            {:ok, %{"ok" => true}}

          row["status"] in @terminal_statuses ->
            {:ok, %{"ok" => true}}

          true ->
            sql = """
            UPDATE #{status_table}
            SET status = 'ENQUEUED',
                queue_name = $2,
                recovery_attempts = 0,
                workflow_deadline_epoch_ms = NULL,
                deduplication_id = NULL,
                started_at_epoch_ms = NULL,
                updated_at = #{ExSql.now_epoch_ms_fragment()}
            WHERE workflow_uuid = $1
            """

            case SQL.query(client.repo, sql, [workflow_id, @internal_queue]) do
              {:ok, _} -> {:ok, %{"ok" => true}}
              {:error, reason} -> {:error, reason}
            end
        end
      end
    end)
    |> unwrap_tx()
  end

  @spec fork_workflow(Client.t(), String.t(), integer(), map()) :: {:ok, map()} | {:error, term()}
  def fork_workflow(client, original_workflow_id, start_step, params) do
    status_table = System.workflow_status_table(client)
    op_outputs_table = System.operation_outputs_table(client)
    events_hist_table = System.workflow_events_history_table(client)
    events_table = System.workflow_events_table(client)
    streams_table = System.streams_table(client)

    forked_workflow_id = Map.get(params, "new_workflow_id") || Ecto.UUID.generate()
    application_version = Map.get(params, "application_version")

    client.repo.transaction(fn ->
      with {:ok, source} <- fetch_workflow_for_fork(client, status_table, original_workflow_id),
           false <- is_nil(source) do
        :ok =
          insert_forked_workflow(
            client,
            status_table,
            forked_workflow_id,
            original_workflow_id,
            source,
            application_version
          )

        if start_step > 1 do
          :ok =
            copy_operation_outputs(
              client,
              op_outputs_table,
              forked_workflow_id,
              original_workflow_id,
              start_step
            )

          :ok =
            copy_events_history(
              client,
              events_hist_table,
              forked_workflow_id,
              original_workflow_id,
              start_step
            )

          :ok =
            copy_latest_events(
              client,
              events_hist_table,
              events_table,
              forked_workflow_id,
              original_workflow_id,
              start_step
            )

          :ok =
            copy_streams(
              client,
              streams_table,
              forked_workflow_id,
              original_workflow_id,
              start_step
            )
        end

        {:ok, %{"ok" => true, "workflow_id" => forked_workflow_id}}
      else
        true ->
          {:error, %{status: 404, body: %{"error" => "Workflow not found"}}}

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> unwrap_tx()
  end

  defp fetch_status(client, status_table, workflow_id) do
    case SQL.query(client.repo, "SELECT status FROM #{status_table} WHERE workflow_uuid = $1", [
           workflow_id
         ]) do
      {:ok, %{rows: []}} ->
        {:ok, nil}

      {:ok, %{rows: [[status]], columns: ["status"]}} ->
        {:ok, %{"status" => status}}

      {:ok, %{rows: [[status]]}} ->
        {:ok, %{"status" => status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_workflow_for_fork(client, status_table, workflow_id) do
    sql = """
    SELECT name, class_name, config_name, application_version, application_id,
           authenticated_user, authenticated_roles, assumed_role, inputs
    FROM #{status_table}
    WHERE workflow_uuid = $1
    """

    case SQL.query(client.repo, sql, [workflow_id]) do
      {:ok, %{rows: []}} ->
        {:ok, nil}

      {:ok,
       %{
         rows: [
           [
             name,
             class_name,
             config_name,
             current_app_version,
             app_id,
             auth_user,
             auth_roles,
             assumed_role,
             inputs
           ]
         ]
       }} ->
        {:ok,
         %{
           "name" => name,
           "class_name" => class_name,
           "config_name" => config_name,
           "application_version" => current_app_version,
           "application_id" => app_id,
           "authenticated_user" => auth_user,
           "authenticated_roles" => auth_roles,
           "assumed_role" => assumed_role,
           "inputs" => inputs
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_forked_workflow(
         client,
         status_table,
         forked_workflow_id,
         original_workflow_id,
         source,
         application_version
       ) do
    app_version =
      if is_nil(application_version), do: source["application_version"], else: application_version

    sql = """
    INSERT INTO #{status_table} (
      workflow_uuid, status, name, class_name, config_name, application_version,
      application_id, authenticated_user, authenticated_roles, assumed_role,
      queue_name, inputs, forked_from
    ) VALUES ($1, 'ENQUEUED', $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
    """

    case SQL.query(client.repo, sql, [
           forked_workflow_id,
           source["name"],
           source["class_name"],
           source["config_name"],
           app_version,
           source["application_id"],
           source["authenticated_user"],
           source["authenticated_roles"],
           source["assumed_role"],
           @internal_queue,
           source["inputs"],
           original_workflow_id
         ]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, message: "failed to insert forked workflow: #{inspect(reason)}"
    end
  end

  defp copy_operation_outputs(client, table, forked_id, original_id, start_step) do
    sql = """
    INSERT INTO #{table} (
      workflow_uuid, function_id, output, error, function_name,
      child_workflow_id, started_at_epoch_ms, completed_at_epoch_ms
    )
    SELECT $1, function_id, output, error, function_name,
           child_workflow_id, started_at_epoch_ms, completed_at_epoch_ms
    FROM #{table}
    WHERE workflow_uuid = $2 AND function_id < $3
    """

    case SQL.query(client.repo, sql, [forked_id, original_id, start_step]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, message: "failed to copy operation outputs: #{inspect(reason)}"
    end
  end

  defp copy_events_history(client, table, forked_id, original_id, start_step) do
    sql = """
    INSERT INTO #{table} (workflow_uuid, function_id, key, value)
    SELECT $1, function_id, key, value
    FROM #{table}
    WHERE workflow_uuid = $2 AND function_id < $3
    """

    case SQL.query(client.repo, sql, [forked_id, original_id, start_step]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, message: "failed to copy events history: #{inspect(reason)}"
    end
  end

  defp copy_latest_events(client, history_table, events_table, forked_id, original_id, start_step) do
    sql = """
    INSERT INTO #{events_table} (workflow_uuid, key, value)
    SELECT $1, weh1.key, weh1.value
    FROM #{history_table} weh1
    WHERE weh1.workflow_uuid = $2
      AND weh1.function_id = (
        SELECT max(weh2.function_id)
        FROM #{history_table} weh2
        WHERE weh2.workflow_uuid = $2
          AND weh2.key = weh1.key
          AND weh2.function_id < $3
      )
    """

    case SQL.query(client.repo, sql, [forked_id, original_id, start_step]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, message: "failed to copy latest events: #{inspect(reason)}"
    end
  end

  defp copy_streams(client, table, forked_id, original_id, start_step) do
    sql = """
    INSERT INTO #{table} (workflow_uuid, function_id, key, value, offset)
    SELECT $1, function_id, key, value, offset
    FROM #{table}
    WHERE workflow_uuid = $2 AND function_id < $3
    """

    case SQL.query(client.repo, sql, [forked_id, original_id, start_step]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        raise RuntimeError, message: "failed to copy streams: #{inspect(reason)}"
    end
  end

  defp unwrap_tx({:ok, {:ok, payload}}), do: {:ok, payload}
  defp unwrap_tx({:ok, {:error, error}}), do: {:error, error}
  defp unwrap_tx({:error, error}), do: {:error, error}
end
