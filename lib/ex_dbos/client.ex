defmodule ExDbos.Client do
  @moduledoc """
  Runtime client configuration for ExDbos operations.
  """

  alias ExDbos.SQL

  @enforce_keys [:repo]
  defstruct repo: nil,
            system_schema: "dbos",
            idempotency_schema: "public",
            idempotency_table: "control_api_idempotency"

  @type t :: %__MODULE__{
          repo: module(),
          system_schema: String.t(),
          idempotency_schema: String.t(),
          idempotency_table: String.t()
        }

  @spec new(keyword()) :: t()
  def new(opts) do
    repo = Keyword.fetch!(opts, :repo)

    %__MODULE__{
      repo: repo,
      system_schema: Keyword.get(opts, :system_schema, "dbos"),
      idempotency_schema: Keyword.get(opts, :idempotency_schema, "public"),
      idempotency_table: Keyword.get(opts, :idempotency_table, "control_api_idempotency")
    }
  end

  @spec system_table(t(), String.t()) :: String.t()
  def system_table(%__MODULE__{system_schema: schema}, table_name) do
    SQL.qualified_table!(schema, table_name)
  end

  @spec idempotency_table(t()) :: String.t()
  def idempotency_table(%__MODULE__{idempotency_schema: schema, idempotency_table: table}) do
    SQL.qualified_table!(schema, table)
  end
end
