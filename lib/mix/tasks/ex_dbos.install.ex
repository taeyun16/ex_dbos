defmodule Mix.Tasks.ExDbos.Install do
  @shortdoc "Installs ex_dbos migration templates into the current project"

  @moduledoc false
  use Mix.Task

  @impl true
  def run(args) do
    installer().install(args: args)
  end

  defp installer, do: Application.get_env(:ex_dbos, :installer_module, ExDbos.Install)
end
