defmodule ExDbos.Idempotency do
  @moduledoc """
  Idempotency reservation/replay behavior for mutation endpoints.
  """

  alias Ecto.Adapters.SQL
  alias ExDbos.{Client, Schema.Idempotency}

  @default_ttl_days 7
  @default_cleanup_interval_seconds 300
  @cleanup_table :ex_dbos_cleanup_state

  @spec with_idempotency(Client.t(), String.t(), String.t(), String.t(), keyword(), (-> {:ok, map()} | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def with_idempotency(client, action, workflow_id, request_key, opts, operation) do
    with :ok <- validate_request_key(request_key),
         :ok <- ensure_table(client),
         :ok <- maybe_cleanup(client, opts),
         {:ok, reservation} <- reserve_or_replay(client, action, workflow_id, request_key) do
      case reservation do
        :new ->
          case operation.() do
            {:ok, payload} ->
              :ok = mark_succeeded(client, request_key, payload)
              {:ok, Map.merge(payload, %{"idempotency_key" => request_key, "idempotency_replayed" => false})}

            {:error, reason} ->
              :ok = mark_failed(client, request_key, inspect(reason))
              {:error, reason}
          end

        {:replay, payload} ->
          replay_payload = if is_map(payload), do: payload, else: %{"result" => payload}
          {:ok, Map.merge(replay_payload, %{"idempotency_key" => request_key, "idempotency_replayed" => true})}
      end
    end
  end

  @spec cleanup_expired(Client.t(), keyword()) :: :ok | {:error, term()}
  def cleanup_expired(client, opts \\ []) do
    ttl_days = Keyword.get(opts, :ttl_days, @default_ttl_days)
    table = Idempotency.table(client)

    sql = """
    DELETE FROM #{table}
    WHERE updated_at < NOW() - make_interval(days => $1)
    """

    case SQL.query(client.repo, sql, [ttl_days]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_request_key(key) when not is_binary(key), do: {:error, %{status: 400, body: %{"error" => "Invalid idempotency key"}}}
  defp validate_request_key(""), do: {:error, %{status: 400, body: %{"error" => "Idempotency key must not be empty"}}}

  defp validate_request_key(key) do
    if byte_size(String.trim(key)) > 200 do
      {:error, %{status: 400, body: %{"error" => "Idempotency key is too long (max 200 chars)"}}}
    else
      :ok
    end
  end

  defp ensure_table(client) do
    table = Idempotency.table(client)

    create_table_sql = """
    CREATE TABLE IF NOT EXISTS #{table} (
      request_key TEXT PRIMARY KEY,
      action TEXT NOT NULL,
      workflow_id TEXT NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('in_progress', 'succeeded', 'failed')),
      response_json JSONB,
      error_message TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
    """

    create_index_sql = """
    CREATE INDEX IF NOT EXISTS control_api_idempotency_action_workflow_idx
    ON #{table} (action, workflow_id)
    """

    with {:ok, _} <- SQL.query(client.repo, create_table_sql, []),
         {:ok, _} <- SQL.query(client.repo, create_index_sql, []) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp reserve_or_replay(client, action, workflow_id, request_key) do
    table = Idempotency.table(client)

    client.repo.transaction(fn ->
      insert_sql = """
      INSERT INTO #{table} (request_key, action, workflow_id, status, created_at, updated_at)
      VALUES ($1, $2, $3, 'in_progress', NOW(), NOW())
      ON CONFLICT (request_key) DO NOTHING
      RETURNING request_key
      """

      case SQL.query(client.repo, insert_sql, [request_key, action, workflow_id]) do
        {:ok, %{rows: [[_]]}} ->
          {:ok, :new}

        {:ok, %{rows: []}} ->
          fetch_sql = """
          SELECT action, workflow_id, status, response_json, error_message
          FROM #{table}
          WHERE request_key = $1
          """

          case SQL.query(client.repo, fetch_sql, [request_key]) do
            {:ok, %{rows: [[stored_action, stored_workflow_id, status, response_json, error_message]]}} ->
              cond do
                stored_action != action or stored_workflow_id != workflow_id ->
                  {:error, %{status: 409, body: %{"error" => "Idempotency key was already used for a different action/workflow"}}}

                status == "succeeded" ->
                  {:ok, {:replay, decode_json(response_json)}}

                status == "failed" ->
                  {:error, %{status: 409, body: %{"error" => "Previous request with this idempotency key failed: #{error_message || "unknown error"}"}}}

                true ->
                  {:error, %{status: 409, body: %{"error" => "A request with this idempotency key is still in progress"}}}
              end

            {:ok, %{rows: []}} ->
              {:error, %{status: 500, body: %{"error" => "Failed to resolve idempotency state"}}}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end)
    |> unwrap_tx()
  end

  defp mark_succeeded(client, request_key, payload) do
    table = Idempotency.table(client)
    encoded_payload = Jason.encode!(payload)

    sql = """
    UPDATE #{table}
    SET status = 'succeeded',
        response_json = $1::jsonb,
        error_message = NULL,
        updated_at = NOW()
    WHERE request_key = $2
    """

    case SQL.query(client.repo, sql, [encoded_payload, request_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> raise RuntimeError, message: "failed to mark idempotency success: #{inspect(reason)}"
    end
  end

  defp mark_failed(client, request_key, error_message) do
    table = Idempotency.table(client)

    sql = """
    UPDATE #{table}
    SET status = 'failed',
        error_message = $1,
        updated_at = NOW()
    WHERE request_key = $2
    """

    message = String.slice(error_message, 0, 4000)

    case SQL.query(client.repo, sql, [message, request_key]) do
      {:ok, _} -> :ok
      {:error, reason} -> raise RuntimeError, message: "failed to mark idempotency failure: #{inspect(reason)}"
    end
  end

  defp maybe_cleanup(client, opts) do
    cleanup_interval = Keyword.get(opts, :cleanup_interval_seconds, @default_cleanup_interval_seconds)
    now = System.monotonic_time(:second)
    key = cleanup_key(client)

    ensure_cleanup_table()

    case :ets.lookup(@cleanup_table, key) do
      [{^key, last}] when now - last < cleanup_interval ->
        :ok

      _ ->
        case cleanup_expired(client, opts) do
          :ok ->
            :ets.insert(@cleanup_table, {key, now})
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp cleanup_key(client) do
    "#{client.idempotency_schema}.#{client.idempotency_table}"
  end

  defp ensure_cleanup_table do
    case :ets.whereis(@cleanup_table) do
      :undefined -> :ets.new(@cleanup_table, [:named_table, :public, :set, read_concurrency: true])
      _ -> :ok
    end

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp decode_json(nil), do: %{}
  defp decode_json(map) when is_map(map), do: map

  defp decode_json(binary) when is_binary(binary) do
    case Jason.decode(binary) do
      {:ok, decoded} -> decoded
      _ -> %{"result" => binary}
    end
  end

  defp unwrap_tx({:ok, {:ok, value}}), do: {:ok, value}
  defp unwrap_tx({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_tx({:error, reason}), do: {:error, reason}
end
