defmodule ExDbos.Schema.Idempotency do
  @moduledoc false

  alias ExDbos.Client

  def table(client), do: Client.idempotency_table(client)
end
