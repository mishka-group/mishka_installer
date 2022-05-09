defmodule MishkaInstallerTest.Installer.DepHandler do
  use ExUnit.Case, async: true
  doctest MishkaInstaller
  alias MishkaInstaller.Installer.DepHandler

  # These are the sample dependencies we are using in MishkaCms
  # We do not test is_there_update and is_there_update/1 function, because this function is a normal get state from a genserver
  # We do not test dependency_changes_notifier/2, because this function is a normal get state from a genserver and the event hook was tested
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

    test "Compare dependencies with json", %{repo_data: _repo_data}  do
      DepHandler.create_deps_json_file(File.cwd!())
      DepHandler.check_or_create_deps_json()
      [] = assert DepHandler.compare_dependencies_with_json()
      # TODO: Add a test consider installed app
    end

    test "Compare sub dependencies with json", %{repo_data: _repo_data}  do
      DepHandler.create_deps_json_file(File.cwd!())
      DepHandler.check_or_create_deps_json()
      [] = assert DepHandler.compare_sub_dependencies_with_json()
      # TODO: Add a test consider installed app with sub dependencies
    end

    test "Get deps from mix", %{repo_data: _repo_data}  do
      [
        %{app: :phoenix_pubsub, version: "~> 2.1"},
        %{app: :ecto_enum, version: "~> 1.4"},
        %{app: :mishka_developer_tools, version: "~> 0.0.6"},
        %{app: :jason, version: "~> 1.3"},
        %{app: :finch, version: "~> 0.12.0"},
        %{app: :ex_doc, version: ">= 0.0.0"}
      ] = assert DepHandler.get_deps_from_mix(MishkaInstaller.MixProject)
    end

    test "Get deps from mix lock", %{repo_data: _repo_data}  do
      true = assert is_list(DepHandler.get_deps_from_mix_lock())
    end

    test "Get extensions json path", %{repo_data: _repo_data}  do
      true = assert DepHandler.extensions_json_path()
      |> is_binary()
    end
  end

  defp clean_json_file() do
    DepHandler.extensions_json_path()
    |> File.rm_rf()
  end
end
