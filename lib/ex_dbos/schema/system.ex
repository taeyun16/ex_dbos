defmodule ExDbos.Schema.System do
  @moduledoc false

  alias ExDbos.Client

  def workflow_status_table(client), do: Client.system_table(client, "workflow_status")
  def operation_outputs_table(client), do: Client.system_table(client, "operation_outputs")
  def workflow_events_table(client), do: Client.system_table(client, "workflow_events")

  def workflow_events_history_table(client), do: Client.system_table(client, "workflow_events_history")

  def streams_table(client), do: Client.system_table(client, "streams")
end
