defmodule Mix.Tasks.ExDbos.Install do
  @shortdoc "Installs ex_dbos migration templates into the current project"

  use Mix.Task

  @impl true
  def run(_args) do
    migrations_dir = Path.join(["priv", "repo", "migrations"])
    File.mkdir_p!(migrations_dir)

    target_file =
      Path.join(
        migrations_dir,
        "#{timestamp()}_create_control_api_idempotency.exs"
      )

    source_file =
      Path.join([:code.priv_dir(:ex_dbos), "templates", "migrations", "create_control_api_idempotency.exs"])

    if migration_exists?(migrations_dir) do
      Mix.shell().info("control_api_idempotency migration already exists, skipping.")
    else
      File.cp!(source_file, target_file)
      Mix.shell().info("Created migration: #{target_file}")
    end
  end

  defp migration_exists?(migrations_dir) do
    migrations_dir
    |> File.ls!()
    |> Enum.any?(&String.ends_with?(&1, "_create_control_api_idempotency.exs"))
  end

  defp timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [
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
