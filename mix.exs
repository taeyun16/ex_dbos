defmodule ExDbos.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_dbos,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      package: package(),
      description: description(),
      test_coverage: test_coverage(),
      docs: docs()
    ]
  end

  def cli do
    [preferred_envs: preferred_cli_env()]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ExDbos.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.13"},
      {:jason, "~> 1.4"},
      {:postgrex, ">= 0.0.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18.5", only: :test, runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      style: ["format"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "test --cover",
        "credo --strict --ignore Credo.Check.Refactor.Nesting,Credo.Check.Refactor.CyclomaticComplexity,Credo.Check.Readability.ModuleNames",
        "deps.audit"
      ],
      "docs.check": ["test test/documentation_consistency_test.exs"],
      coverage: ["test --cover"],
      "test.integration": ["test --include integration"]
    ]
  end

  defp preferred_cli_env do
    [
      quality: :test,
      style: :dev,
      "docs.check": :test,
      coverage: :test,
      "test.integration": :test,
      coveralls: :test,
      "coveralls.detail": :test,
      "coveralls.post": :test,
      "coveralls.html": :test
    ]
  end

  defp test_coverage do
    [
      output: "cover",
      summary: [threshold: 80],
      ignore_modules: [
        ExDbos.Application,
        ExDbos.Schema.System,
        ExDbos.Schema.Idempotency
      ]
    ]
  end

  defp description do
    "DBOS control SDK for Elixir (2.11.x system schema compatible)"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/taeyun16/ex_dbos"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/README.md",
        "docs/bootstrap.md",
        "docs/quickstart.md",
        "docs/docker-compose-workflow.md",
        "docs/control-api.md",
        "docs/idempotency.md",
        "docs/troubleshooting.md"
      ]
    ]
  end
end
