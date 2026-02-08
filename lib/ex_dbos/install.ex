defmodule ExDbos.Install do
  @moduledoc false

  @migration_suffix "_create_control_api_idempotency.exs"

  @spec install(keyword()) :: :ok
  def install(opts \\ []) do
    fs = Keyword.get(opts, :fs, File)
    migrations_dir = Keyword.get(opts, :migrations_dir, Path.join(["priv", "repo", "migrations"]))
    source_file = Keyword.get(opts, :source_file, default_source_file())
    timestamp = Keyword.get(opts, :timestamp, timestamp())
    log = Keyword.get(opts, :log, fn message -> Mix.shell().info(message) end)

    fs.mkdir_p!(migrations_dir)

    if migration_exists?(fs, migrations_dir) do
      log.("control_api_idempotency migration already exists, skipping.")
    else
      target_file = Path.join(migrations_dir, "#{timestamp}#{@migration_suffix}")
      fs.cp!(source_file, target_file)
      log.("Created migration: #{target_file}")
    end

    :ok
  end

  defp migration_exists?(fs, migrations_dir) do
    migrations_dir
    |> fs.ls!()
    |> Enum.any?(&String.ends_with?(&1, @migration_suffix))
  end

  defp default_source_file do
    Path.join([
      :code.priv_dir(:ex_dbos),
      "templates",
      "migrations",
      "create_control_api_idempotency.exs"
    ])
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    "~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B"
    |> :io_lib.format([
      year,
      month,
      day,
      hour,
      minute,
      second
    ])
    |> to_string()
  end
end
