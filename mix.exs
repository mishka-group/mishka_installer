defmodule MishkaInstaller.MixProject do
  use Mix.Project

  @version "0.1.5"
  @source_url "https://github.com/mishka-group/mishka_installer"

  def project do
    [
      app: :mishka_installer,
      version: @version,
      elixir: "~> 1.17",
      name: "Mishka installer",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      homepage_url: "https://github.com/mishka-group",
      source_url: @source_url,
      docs: docs(),
      test_coverage: [
        ignore_modules: [
          MishkaInstaller.MnesiaRepo.State,
          MishkaInstaller.MnesiaRepo,
          MishkaInstaller.Installer.CompileHandler,
          ~r/\.Support\./
        ]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {MishkaInstaller.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.2"},
      {:req, "~> 0.6.1"},
      {:plug, "~> 1.19"},

      # Schema validation + sanitizing
      {:guarded_struct, "~> 0.1.0-beta.8"},
      # Telemetry instrumentation
      {:telemetry, "~> 1.4"},

      # Dev and Test dependencies
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Mishka Installer is a system plugin manager and run time installer for elixir."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs LICENSE README* Changelog.md),
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "https://hexdocs.pm/mishka_installer/changelog.html"
      }
    ]
  end

  defp docs() do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md"
      ],
      source_url: @source_url
    ]
  end
end
