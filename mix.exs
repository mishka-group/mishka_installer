defmodule MishkaInstaller.MixProject do
  use Mix.Project

  @version "0.1.15"
  @source_url "https://github.com/mishka-group/mishka_installer"

  def project do
    [
      app: :mishka_installer,
      version: @version,
      elixir: "~> 1.17",
      name: "Mishka Installer",
      elixirc_paths: elixirc_paths(Mix.env()),
      # The release restart fixture's source lives under test/ but isn't ExUnit — don't warn on it.
      test_ignore_filters: [&String.starts_with?(&1, "test/integration/")],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [ignore_warnings: ".dialyzer_ignore.exs"],
      description: description(),
      package: package(),
      homepage_url: "https://mishka.tools/installer",
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

  def cli do
    [preferred_envs: [ci: :test]]
  end

  def application do
    [
      extra_applications: [:logger, :mnesia],
      mod: {MishkaInstaller.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.3"},
      {:req, "~> 0.7"},
      {:plug, "~> 1.20"},

      # Schema validation + sanitizing
      {:guarded_struct, "~> 0.1.1"},
      # Telemetry instrumentation
      {:telemetry, "~> 1.4"},
      # Plugin dependency graph: cycle detection + start ordering
      {:libgraph, "~> 0.16"},

      # Dev and Test dependencies
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false},

      # Static analysis and security tooling
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.6", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "hex.audit",
        "deps.audit",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow --config",
        "dialyzer",
        "ex_dna --max-clones 0",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Mishka Installer is a system plugin manager and run time installer for elixir."
  end

  defp package() do
    [
      files: ~w(lib .formatter.exs mix.exs LICENSE README* CHANGELOG.md),
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      links: %{
        "Mishka Installer" => "https://mishka.tools/installer",
        "Official document" => "https://mishka.tools/installer/docs",
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/master/CHANGELOG.md",
        "Sponsor" => "https://github.com/sponsors/mishka-group",
        "Contributors" => "#{@source_url}/graphs/contributors"
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
