defmodule ExDbos.Bootstrap do
  @moduledoc """
  Startup preflight checks for an existing DBOS system database.

  These checks are intentionally read-only and are designed to be called
  during your application's startup path.
  """

  alias ExDbos.Client

  @required_system_tables [
    "workflow_status",
    "operation_outputs",
    "workflow_events",
    "workflow_events_history",
    "streams"
  ]

  @type check_error :: %{
          check: :health | :system_tables | :idempotency_table,
          message: String.t(),
          details: map(),
          reason: term() | nil
        }

  @spec run(Client.t(), keyword()) :: :ok | {:error, check_error()}
  def run(client, opts \\ []) do
    with :ok <- check_health(client),
         :ok <- check_system_tables(client, opts) do
      maybe_check_idempotency_table(client, opts)
    end
  end

  @spec run!(Client.t(), keyword()) :: :ok
  def run!(client, opts \\ []) do
    case run(client, opts) do
      :ok ->
        :ok

      {:error, %{message: message} = error} ->
        raise RuntimeError,
          message: "ex_dbos bootstrap failed (#{error.check}): #{message} #{inspect(error.details)}"
    end
  end

  defp check_health(client) do
    case sql_module(client).query(client.repo, "SELECT 1", []) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        {:error,
         %{
           check: :health,
           message: "database health check failed",
           details: %{},
           reason: reason
         }}
    end
  end

  defp check_system_tables(client, opts) do
    expected = Keyword.get(opts, :required_system_tables, @required_system_tables)

    sql = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = $1
      AND table_name = ANY($2::text[])
    """

    case sql_module(client).query(client.repo, sql, [client.system_schema, expected]) do
      {:ok, %{rows: rows}} ->
        found =
          MapSet.new(rows, fn [table_name] -> table_name end)

        missing = Enum.reject(expected, &MapSet.member?(found, &1))

        if missing == [] do
          :ok
        else
          {:error,
           %{
             check: :system_tables,
             message: "missing DBOS system tables",
             details: %{system_schema: client.system_schema, missing_tables: missing},
             reason: nil
           }}
        end

      {:error, reason} ->
        {:error,
         %{
           check: :system_tables,
           message: "failed to inspect DBOS system tables",
           details: %{system_schema: client.system_schema, expected_tables: expected},
           reason: reason
         }}
    end
  end

  defp maybe_check_idempotency_table(client, opts) do
    if Keyword.get(opts, :check_idempotency_table, true) do
      check_idempotency_table(client)
    else
      :ok
    end
  end

  defp check_idempotency_table(client) do
    sql = """
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = $1
      AND table_name = $2
    LIMIT 1
    """

    case sql_module(client).query(client.repo, sql, [
           client.idempotency_schema,
           client.idempotency_table
         ]) do
      {:ok, %{rows: [[_]]}} ->
        :ok

      {:ok, %{rows: []}} ->
        {:error,
         %{
           check: :idempotency_table,
           message: "idempotency table does not exist",
           details: %{
             idempotency_schema: client.idempotency_schema,
             idempotency_table: client.idempotency_table
           },
           reason: nil
         }}

      {:error, reason} ->
        {:error,
         %{
           check: :idempotency_table,
           message: "failed to inspect idempotency table",
           details: %{
             idempotency_schema: client.idempotency_schema,
             idempotency_table: client.idempotency_table
           },
           reason: reason
         }}
    end
  end

  defp sql_module(%Client{sql_module: module}), do: module
end
