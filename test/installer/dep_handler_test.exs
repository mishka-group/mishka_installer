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
    [this: "what_it_is"]
  end

  setup _context do
    {:ok, :add_new_app, repo_data} = assert DepHandler.add_new_app(@old_ueberauth)
    on_exit fn ->
      clean_json_file()
      MishkaInstaller.Dependency.delete(repo_data.id)
    end
    [repo_data: repo_data]
  end

  describe "Happy | DepHandler module (▰˘◡˘▰)" do
    test "Create mix deps list from json file", %{repo_data: _repo_data} do
      DepHandler.create_deps_json_file(File.cwd!())
      {:ok, :check_or_create_deps_json, _json_data} = assert DepHandler.check_or_create_deps_json()
      [{:ueberauth, "~> 0.6.3"}] = assert DepHandler.mix_read_from_json()
    end

    test "Read a json", %{repo_data: _repo_data} do
      {:ok, :read_dep_json, _data} = assert DepHandler.read_dep_json("[]")
      {:error, :read_dep_json, _msg} = assert DepHandler.read_dep_json("]")
    end

    test "Create mix deps in mix file", %{repo_data: _repo_data} do
      DepHandler.create_deps_json_file(File.cwd!())
      DepHandler.check_or_create_deps_json()
      list = [{:finch, "~> 0.12.0"}, {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}]
      [{:finch, "~> 0.12.0"}, {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}, {:ueberauth, "~> 0.6.3"}] = assert DepHandler.append_mix(list)
    end
  end

  defp clean_json_file() do
    DepHandler.extensions_json_path()
    |> File.rm_rf()
  end
end
