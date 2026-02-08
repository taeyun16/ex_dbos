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
      docs: docs()
    ]
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
      {:styler, "~> 1.10", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      style: ["format"]
    ]
  end

  defp description do
    "DBOS control SDK for Elixir (2.11.x system schema compatible)"
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/dbos-inc/ex_dbos"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
