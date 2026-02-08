defmodule ExDbos.DocumentationConsistencyTest do
  use ExUnit.Case, async: true

  @project_root Path.expand("..", __DIR__)
  @readme_path Path.join(@project_root, "README.md")
  @docs_dir Path.join(@project_root, "docs")
  @doc_files [@readme_path | Path.wildcard(Path.join(@docs_dir, "*.md"))]

  defmodule RepoStub do
    @moduledoc false
  end

  test "all relative markdown links resolve to existing files" do
    Enum.each(@doc_files, fn file ->
      file
      |> File.read!()
      |> extract_links()
      |> Enum.filter(&relative_link?/1)
      |> Enum.each(fn link ->
        target =
          link
          |> String.split("#", parts: 2)
          |> hd()
          |> String.split("?", parts: 2)
          |> hd()

        resolved = Path.expand(target, Path.dirname(file))

        assert File.exists?(resolved),
               "broken link #{inspect(link)} in #{Path.relative_to(file, @project_root)}"
      end)
    end)
  end

  test "control API docs match exported ExDbos.Control functions" do
    expected = [health: 1, cancel_workflow: 4, resume_workflow: 4, fork_workflow: 5]
    exported = MapSet.new(ExDbos.Control.__info__(:functions))
    control_doc = File.read!(Path.join(@docs_dir, "control-api.md"))

    Enum.each(expected, fn {name, arity} ->
      assert MapSet.member?(exported, {name, arity})
      assert control_doc =~ "`#{name}/#{arity}`"
    end)
  end

  test "documented client defaults match ExDbos.Client defaults" do
    client = ExDbos.Client.new(repo: RepoStub)

    assert client.system_schema == "dbos"
    assert client.idempotency_schema == "public"
    assert client.idempotency_table == "control_api_idempotency"

    readme = File.read!(@readme_path)
    quickstart = File.read!(Path.join(@docs_dir, "quickstart.md"))

    Enum.each([readme, quickstart], fn content ->
      assert content =~ ~s(system_schema: "dbos")
      assert content =~ ~s(idempotency_schema: "public")
      assert content =~ ~s(idempotency_table: "control_api_idempotency")
    end)
  end

  test "idempotency docs match implemented defaults and states" do
    idempotency_doc = File.read!(Path.join(@docs_dir, "idempotency.md"))

    assert idempotency_doc =~ "`ttl_days` (default `7`)"
    assert idempotency_doc =~ "`cleanup_interval_seconds` (default `300`)"
    assert idempotency_doc =~ "`in_progress`, `succeeded`, `failed`"

    migration_template =
      File.read!(Path.join(@project_root, "priv/templates/migrations/create_control_api_idempotency.exs"))

    assert migration_template =~ "status IN ('in_progress', 'succeeded', 'failed')"
  end

  defp extract_links(markdown) do
    ~r/\[[^\]]+\]\(([^)]+)\)/
    |> Regex.scan(markdown, capture: :all_but_first)
    |> List.flatten()
  end

  defp relative_link?(link) do
    not String.starts_with?(link, ["http://", "https://", "mailto:", "#"])
  end
end
