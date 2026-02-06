defmodule ExDbos do
  @moduledoc """
  DBOS control SDK for Elixir.

  This package focuses on control actions:

  - `health`
  - `cancel`
  - `resume`
  - `fork`

  with idempotency semantics compatible with DBOS-Live control API behavior.
  """

  alias ExDbos.Client

  @spec new_client(keyword()) :: Client.t()
  def new_client(opts), do: Client.new(opts)
end
