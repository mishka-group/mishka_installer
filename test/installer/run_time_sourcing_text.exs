defmodule MishkaInstallerTest.Installer.RunTimeSourcing do
  use ExUnit.Case, async: true
  doctest MishkaInstaller

  # @old_ueberauth %DepHandler{
  #   app: "ueberauth",
  #   version: "0.6.3",
  #   type: "hex",
  #   url: "https://hex.pm/packages/ueberauth",
  #   git_tag: nil,
  #   custom_command: nil,
  #   dependency_type: "force_update",
  #   update_server: nil,
  #   dependencies: [
  #     %{app: :plug, min: "1.5"}
  #   ]
  # }

  # @new_ueberauth Map.merge(@old_ueberauth, %{version: "0.7.0"})

  # @ueberauth_google %DepHandler{
  #   app: "ueberauth_google",
  #   version: "0.10.1",
  #   type: "hex",
  #   url: "https://hex.pm/packages/ueberauth_google",
  #   git_tag: nil,
  #   custom_command: nil,
  #   dependency_type: "force_update",
  #   update_server: nil,
  #   dependencies: [
  #     %{app: :oauth2 , min: "2.0"},
  #     %{app: :ueberauth , min: "0.7.0"},
  #   ]
  # }
end
