defmodule ExDbos do
  @moduledoc """
  DBOS control SDK for Elixir.

  This package focuses on control actions:

  - `health`
  - `cancel`
  - `resume`
  - `fork`
  - `bootstrap` preflight checks

  with idempotency semantics compatible with DBOS-Live control API behavior.
  """

  alias ExDbos.Bootstrap
  alias ExDbos.Client

  @spec new_client(keyword()) :: Client.t()
  def new_client(opts), do: Client.new(opts)

  @spec bootstrap(Client.t(), keyword()) :: :ok | {:error, Bootstrap.check_error()}
  def bootstrap(client, opts \\ []), do: Bootstrap.run(client, opts)

  @spec bootstrap!(Client.t(), keyword()) :: :ok
  def bootstrap!(client, opts \\ []), do: Bootstrap.run!(client, opts)
end
