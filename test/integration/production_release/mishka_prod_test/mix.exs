defmodule MishkaProdTest.MixProject do
  use Mix.Project

  # Throwaway host app used by run.sh to prove an installed library survives a `mix release` cold
  # restart. Build artifacts go to a temp dir, NOT under the parent's test/ tree (which `mix test`
  # globs for *_test.exs — this fixture's own deps ship such files).
  def project do
    [
      app: :mishka_prod_test,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: true,
      deps_path: artifacts("deps"),
      build_path: artifacts("_build"),
      deps: deps(),
      releases: [mishka_prod_test: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {MishkaProdTest.Application, []}]
  end

  defp deps do
    [{:mishka_installer, path: "../../../.."}]
  end

  defp artifacts(sub) do
    base =
      System.get_env("MISHKA_FIXTURE_ARTIFACTS") ||
        Path.join(System.tmp_dir!(), "mishka_prod_test_artifacts")

    Path.join(base, sub)
  end
end
