Mix.install([
  {:ecto_sql, "~> 3.13"},
  {:postgrex, ">= 0.0.0"},
  {:ex_dbos, path: "/workspace"}
])

defmodule ComposeSmokeRepo do
  use Ecto.Repo,
    otp_app: :ex_dbos_compose_smoke,
    adapter: Ecto.Adapters.Postgres
end

defmodule ComposeSmoke do
  @idempotency_table_sql """
  CREATE TABLE IF NOT EXISTS public.control_api_idempotency (
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

  @idempotency_index_sql """
  CREATE INDEX IF NOT EXISTS control_api_idempotency_action_workflow_idx
    ON public.control_api_idempotency (action, workflow_id)
  """

  @max_attempts 30
  @attempt_delay_ms 2_000

  def run do
    start_repo!()

    client =
      ExDbos.Client.new(
        repo: ComposeSmokeRepo,
        system_schema: System.get_env("DBOS_SYSTEM_SCHEMA", "dbos"),
        idempotency_schema: "public",
        idempotency_table: "control_api_idempotency"
      )

    wait_for_system_tables!(client)
    ensure_idempotency_table!()
    :ok = ExDbos.bootstrap!(client)
    assert_health!(client)
    assert_idempotency_replay!(client)

    IO.puts("ex_dbos compose smoke check completed successfully")
  end

  defp start_repo! do
    config = [
      username: "postgres",
      password: "dbos",
      hostname: "db",
      port: 5432,
      database: "dbos_example",
      pool_size: 2,
      stacktrace: true,
      show_sensitive_data_on_connection_error: true
    ]

    Application.put_env(:ex_dbos_compose_smoke, ComposeSmokeRepo, config)

    case ComposeSmokeRepo.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "failed to start repo: #{inspect(reason)}"
    end
  end

  defp wait_for_system_tables!(client) do
    1..@max_attempts
    |> Enum.reduce_while(nil, fn attempt, _acc ->
      case ExDbos.bootstrap(client, check_idempotency_table: false) do
        :ok ->
          IO.puts("bootstrap preflight (system tables) succeeded")
          {:halt, :ok}

        {:error, error} ->
          IO.puts("bootstrap preflight retry #{attempt}/#{@max_attempts}: #{inspect(error)}")

          if attempt == @max_attempts do
            raise "DBOS system tables were not ready after #{@max_attempts} attempts"
          else
            Process.sleep(@attempt_delay_ms)
            {:cont, :retry}
          end
      end
    end)
  end

  defp ensure_idempotency_table! do
    case Ecto.Adapters.SQL.query(ComposeSmokeRepo, @idempotency_table_sql, []) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "failed to create idempotency table: #{inspect(reason)}"
    end

    case Ecto.Adapters.SQL.query(ComposeSmokeRepo, @idempotency_index_sql, []) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "failed to create idempotency index: #{inspect(reason)}"
    end
  end

  defp assert_health!(client) do
    case ExDbos.Control.health(client) do
      {:ok, %{"status" => "ok"}} ->
        IO.puts("health check passed")

      other ->
        raise "unexpected health response: #{inspect(other)}"
    end
  end

  defp assert_idempotency_replay!(client) do
    request_key = "compose-smoke-#{System.system_time(:millisecond)}"
    workflow_id = "compose-sample-workflow"

    first =
      ExDbos.Control.cancel_workflow(client, workflow_id, request_key,
        ttl_days: 7,
        cleanup_interval_seconds: 300
      )

    second =
      ExDbos.Control.cancel_workflow(client, workflow_id, request_key,
        ttl_days: 7,
        cleanup_interval_seconds: 300
      )

    case {first, second} do
      {{:ok, first_payload}, {:ok, second_payload}} ->
        unless first_payload["idempotency_replayed"] == false do
          raise "first idempotent response should not be replayed: #{inspect(first_payload)}"
        end

        unless second_payload["idempotency_replayed"] == true do
          raise "second idempotent response should be replayed: #{inspect(second_payload)}"
        end

        IO.puts("idempotency replay check passed")

      other ->
        raise "unexpected idempotency responses: #{inspect(other)}"
    end
  end
end

ComposeSmoke.run()
