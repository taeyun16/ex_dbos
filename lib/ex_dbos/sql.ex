defmodule ExDbos.SQL do
  @moduledoc false

  @identifier ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/

  @spec identifier!(String.t(), String.t()) :: String.t()
  def identifier!(value, label) when is_binary(value) do
    if Regex.match?(@identifier, value) do
      ~s("#{value}")
    else
      raise ArgumentError, "invalid #{label}: #{inspect(value)}"
    end
  end

  @spec qualified_table!(String.t(), String.t()) :: String.t()
  def qualified_table!(schema, table) do
    "#{identifier!(schema, "schema")}.#{identifier!(table, "table")}"
  end

  @spec now_epoch_ms_fragment() :: String.t()
  def now_epoch_ms_fragment, do: "(extract(epoch from now()) * 1000)::bigint"
end
