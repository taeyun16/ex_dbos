defmodule ExDbos.InstallTest do
  use ExUnit.Case, async: true

  alias ExDbos.Install

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "ex_dbos_install_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  test "install/1 copies migration when none exists", %{tmp_dir: tmp_dir} do
    migrations_dir = Path.join(tmp_dir, "priv/repo/migrations")
    source_file = Path.join(tmp_dir, "source/create_control_api_idempotency.exs")

    File.mkdir_p!(Path.dirname(source_file))
    File.write!(source_file, "defmodule SampleMigration do\nend\n")

    log = fn message -> send(self(), {:log, message}) end

    assert :ok =
             Install.install(
               migrations_dir: migrations_dir,
               source_file: source_file,
               timestamp: "20260207010101",
               log: log
             )

    assert File.exists?(Path.join(migrations_dir, "20260207010101_create_control_api_idempotency.exs"))

    assert_received {:log, created_message}
    assert created_message =~ "Created migration:"
  end

  test "install/1 skips copy when migration already exists", %{tmp_dir: tmp_dir} do
    migrations_dir = Path.join(tmp_dir, "priv/repo/migrations")
    source_file = Path.join(tmp_dir, "source/create_control_api_idempotency.exs")

    File.mkdir_p!(migrations_dir)
    File.mkdir_p!(Path.dirname(source_file))

    existing_file = Path.join(migrations_dir, "20250101000000_create_control_api_idempotency.exs")
    File.write!(existing_file, "existing")
    File.write!(source_file, "new source")

    log = fn message -> send(self(), {:log, message}) end

    assert :ok =
             Install.install(
               migrations_dir: migrations_dir,
               source_file: source_file,
               timestamp: "20260207010101",
               log: log
             )

    assert File.read!(existing_file) == "existing"

    refute File.exists?(Path.join(migrations_dir, "20260207010101_create_control_api_idempotency.exs"))

    assert_received {:log, skip_message}
    assert skip_message =~ "already exists, skipping"
  end
end
