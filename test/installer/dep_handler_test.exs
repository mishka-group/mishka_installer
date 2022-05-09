defmodule MishkaInstallerTest.Installer.DepHandler do
  use ExUnit.Case, async: true
  doctest MishkaInstaller
  alias MishkaInstaller.Installer.DepHandler

  # These are the sample dependencies we are using in MishkaCms
  @old_ueberauth %DepHandler{
    app: "ueberauth",
    version: "0.6.3",
    type: "hex",
    url: "https://hex.pm/packages/ueberauth",
    git_tag: nil,
    custom_command: nil,
    dependency_type: "force_update",
    update_server: nil,
    dependencies: [
      %{app: :plug, min: "1.5"}
    ]
  }

  @new_ueberauth Map.merge(@old_ueberauth, %{version: "0.7.0"})

  @ueberauth_google %DepHandler{
    app: "ueberauth_google",
    version: "0.10.1",
    type: "hex",
    url: "https://hex.pm/packages/ueberauth_google",
    git_tag: nil,
    custom_command: nil,
    dependency_type: "force_update",
    update_server: nil,
    dependencies: [
      %{app: :oauth2 , min: "2.0"},
      %{app: :ueberauth , min: "0.7.0"},
    ]
  }

  setup_all _tags do
    clean_json_file()
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Ecto.Integration.TestRepo)
    on_exit fn -> clean_json_file() end
    [this_is: "is"]
  end

  describe "Happy | DepHandler module (▰˘◡˘▰)" do
    test "add a dependency", %{this_is: _this_is} do
      {:ok, :add_new_app, _repo_data} = assert DepHandler.add_new_app(@old_ueberauth)
      {:error, :add_new_app, :changeset, _repo_error} = assert DepHandler.add_new_app(@old_ueberauth)
    end
  end

  defp clean_json_file() do
    DepHandler.extensions_json_path()
    |> File.rm_rf()
  end
end
