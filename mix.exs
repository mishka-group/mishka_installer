defmodule MishkaInstaller.MixProject do
  use Mix.Project

  @version "0.1.0-alpha.1"
  @source_url "https://github.com/mishka-group/mishka_installer"

  def project do
    [
      app: :mishka_installer,
      version: @version,
      elixir: "~> 1.16",
      name: "Mishka installer",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      homepage_url: "https://github.com/mishka-group",
      source_url: @source_url,
      docs: [
        main: "MishkaInstaller",
        source_ref: "master",
        extras: ["README.md"],
        source_url: @source_url
      ],
      test_coverage: [
        ignore_modules: [
          MishkaInstaller.MnesiaRepo.State,
          MishkaInstaller.Installer.PortHandler,
          MishkaInstaller.MnesiaRepo,
          MishkaInstaller.Installer.CompileHandler,
          MishkaInstaller.Installer.Collect,
          Collectable.MishkaInstaller.Installer.Collect,
          ~r/\.Support.MishkaPlugin\./
        ]
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
      {:phoenix_pubsub, "~> 2.1.3"},
      {:req, "~> 0.5.1"},
      {:plug, "~> 1.16"},

      # Extra tools
      {:mishka_developer_tools, "~> 0.1.7"},
      {:telemetry, "~> 1.2.1"},

      # Dev and Test dependencies
      {:ex_doc, "~> 0.34.0", only: :dev, runtime: false},
      {:hex_core, "~> 0.10.2", only: :test}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Mishka Installer is a system plugin manager and run time installer for elixir."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs LICENSE README*),
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
