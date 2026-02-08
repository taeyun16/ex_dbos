defmodule Mix.Tasks.ExDbos.InstallTaskTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.ExDbos.Install

  defmodule InstallerFake do
    @moduledoc false
    def install(opts) do
      send(self(), {:installer_called, opts})
      :ok
    end
  end

  setup do
    previous = Application.get_env(:ex_dbos, :installer_module)
    Application.put_env(:ex_dbos, :installer_module, InstallerFake)

    on_exit(fn ->
      if previous do
        Application.put_env(:ex_dbos, :installer_module, previous)
      else
        Application.delete_env(:ex_dbos, :installer_module)
      end
    end)

    :ok
  end

  test "run/1 delegates to installer module" do
    Install.run(["--sample"])

    assert_received {:installer_called, [args: ["--sample"]]}
  end
end
