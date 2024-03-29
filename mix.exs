defmodule MishkaInstaller.MixProject do
  use Mix.Project
  @version "0.0.4"

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
      xref: [exclude: [EctoEnum.Use]],
      docs: [
        main: "MishkaInstaller",
        source_ref: "master",
        extras: ["README.md"],
        source_url: "https://github.com/mishka-group/mishka_installer"
      ]
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
      {:phoenix_pubsub, "~> 2.1"},
      {:mishka_developer_tools, "~> 0.0.7"},
      {:jason, "~> 1.4"},
      {:finch, "~> 0.13.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:phoenix_live_view, "~> 0.17.9"},
      {:sourceror, "~> 0.11.2"},
      {:ets, "~> 0.9.0"},
      {:oban, "~> 2.13"},
      {:gettext, "~> 0.20.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Mishka Installer is a system plugin manager and run time installer for elixir."
  end

  defp package() do
    [
      files: ~w(lib priv .formatter.exs mix.exs LICENSE README*),
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{"GitHub" => "https://github.com/mishka-group/mishka_installer"}
    ]
  end
end
