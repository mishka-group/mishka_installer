defmodule MishkaInstaller.MixProject do
  use Mix.Project
  @version "0.0.1"

  def project do
    [
      app: :mishka_installer,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Mishka Installer",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      homepage_url: "https://github.com/mishka-group",
      source_url: "https://github.com/mishka-group/mishka_installer",
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MishkaInstaller.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.0"}, # should change it on mishka_developer_tools and remove it from installer mix file
      {:ecto_enum, "~> 1.4"},
      {:ecto_sql, "~> 3.7"}, # should change it on mishka_developer_tools and remove it from installer mix file
      {:postgrex, "~> 0.15.13"},
      {:mishka_developer_tools, "~> 0.0.5"},
      {:jason, "~> 1.3"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Mishka Installer is a system plugin manager for elixir."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs LICENSE README*),
      licenses: ["Apache License 2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{"GitHub" => "https://github.com/mishka-group/mishka_installer"}
    ]
  end
end
