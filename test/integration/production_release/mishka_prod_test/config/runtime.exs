import Config

# Production knobs read at boot from the mounted "volume" dir — mirrors a real deployment.
if config_env() == :prod do
  data =
    System.get_env("MISHKA_DATA_DIR") || Path.join(System.tmp_dir!(), "mishka_prod_test_data")

  config :mishka_installer, :project_path, data
  config :mishka_installer, :project_env, :prod
  config :mishka_installer, :extensions_path, data <> "/extensions"

  config :mishka_installer, MishkaInstaller.MnesiaRepo,
    mnesia_dir: data <> "/mnesia",
    essential: [MishkaInstaller.Event.Event, MishkaInstaller.Installer.Installer]
end
