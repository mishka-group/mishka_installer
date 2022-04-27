defmodule MishkaInstaller.Installer.DepHandler do
  # TODO: Check if this file does not exist, create it with database
  # TODO: Read the installed_app information and existed app in json file, what sub-dependencies need to be updated
  # TODO: Create queue for installing multi deps, and compiling, check oban: https://github.com/sorentwo/oban
  # TODO: Add version of app in extra
  # TODO: Check is there update from a developer json url, and get it from plugin/componnet mix file, Consider queue
  # TODO: Check Conflict with max and mix dependencies, before update with installed or will be installed apps
  # [
  #   %{
  #     app: :mishka_installer,
  #     version: "0.0.2",
  #     type: :git, # :hex, if user upload elixir libraries (path), we should keep them in a temporary folder, and Docker should make it valume
  #     url: "https://github.com/mishka-group/mishka_installer", # if it is hex: https://hex.pm/packages/mishka_installer
  #     git_tag: "0.0.2", # we consider it when it is a git, and if does not exist we get master,
  #     timeout: 3000, # it can be a feature, How long does it take to start?
  #     dependency_type: :none, # :soft_update, When you use this, the RunTime sourcing check what dependencies you use in your program have a higher version
  #     #compared to the old source. it just notice admin there is a update, it does not force the source to be updated
  #     dependencies: [ # this part let mishka_installer to know can update or not dependencies of a app, we should consider a backup file
  #       %{app: :mishka_developer_tools, max: "0.0.2", min: "0.0.1"},
  #       %{app: :mishka_social, max: "0.0.2", min: "0.0.1"}
  #     ],
  #     update_server: "https://github.com/mishka-group/mishka_installer/blob/master/update.json", # Check is there a higher version?
  #   }
  # ]

  defstruct [:app, :version, :type, :url, :git_tag, :timeout, :dependency_type, :update_server, dependencies: []]

  @type t() :: %__MODULE__{
    app: String.t(),
    version: String.t(),
    type: String.t(),
    url: String.t(),
    git_tag: String.t(),
    timeout: timeout(),
    dependency_type: String.t(),
    update_server: String.t(),
    dependencies: [map()],
  }

  @spec add_new_app(MishkaInstaller.Installer.DepHandler.t()) :: :ok | {:error, atom} | {:error, :add_new_app, String.t()}
  def add_new_app(%__MODULE__{} = app_info) do
    case check_or_create_deps_json() do
      {:ok, :check_or_create_deps_json, exist_json} ->
        update_file({:open_file, File.open(extensions_json_path(), [:write])}, app_info, exist_json)
      {:error, :check_or_create_deps_json, msg} -> {:error, :add_new_app, msg}
    end
  end

  @spec check_or_create_deps_json(binary) :: {:ok, :check_or_create_deps_json, String.t()} | {:error, :check_or_create_deps_json, String.t()}
  def check_or_create_deps_json(project_path \\ MishkaInstaller.get_config(:project_path) || File.cwd!()) do
    with {:deployment_path, true} <- {:deployment_path, File.exists?(Path.join(project_path, ["deployment"]))},
         {:extensions_path, true} <- {:extensions_path, File.exists?(Path.join(project_path, ["deployment/", "extensions"]))},
         {:json_file, true} <- {:json_file, File.exists?(extensions_json_path())} do

         {:ok, :check_or_create_deps_json, File.read!(extensions_json_path())}
    else
      {:deployment_path, false} ->
        create_deps_json_directory(project_path, "deployment")
      {:extensions_path, false} ->
        create_deps_json_directory(project_path, "deployment/extensions")
      {:json_file, false} ->
        create_deps_json_file(project_path)
    end
  end

  def get_deps_from_mix(mix_module) do
    [{:deps, app_info} | _t] = Keyword.filter(mix_module.project, fn {key, _value} -> key == :deps end)
    Enum.map(app_info, fn app_info ->
      [app, version] = Tuple.to_list(app_info) |> Enum.take(2)
      %{app: app, version: version}
    end)
  end

  def get_deps_from_mix_lock() do
    Mix.Dep.Lock.read
    |> Map.to_list()
    |> Enum.map(fn {key, list} ->
      [_h | [_app, version]] = Tuple.to_list(list) |> Enum.take(3)
      %{app: key, version: version}
    end)
  end

  def read_dep_json() do
    File.read!(extensions_json_path())
    |> Jason.decode!()
  rescue
    _e -> {:error, "You do not have access to read this file or maybe the file does not exist or even has syntax error"}
  end

  defp create_deps_json_directory(project_path, folder_path) do
    case File.mkdir(Path.join(project_path, folder_path)) do
      :ok -> check_or_create_deps_json(project_path)
      {:error, :eacces} -> {:error, :check_or_create_deps_json, "You do not have sufficient access to create this directory. Please add it manually."}
      {:error, :enospc} -> {:error, :check_or_create_deps_json, "there is no space left on the device."}
      {:error, e} when e in [:eexist, :enoent, :enotdir] ->
        {:error, :check_or_create_deps_json, "Please contact plugin support when you encounter this error."}
    end
  end

  defp create_deps_json_file(project_path) do
    case File.open(extensions_json_path(), [:write]) do
      {:ok, file} ->
        IO.binwrite(file, Jason.encode!([]))
        File.close(file)
        check_or_create_deps_json(project_path)
      _error -> {:error, :check_or_create_deps_json, "You do not have sufficient access to create this file. Please add it manually."}
    end
  end

  defp extensions_json_path() do
    MishkaInstaller.get_config(:project_path) || File.cwd!()
    |> Path.join(["deployment/", "extensions/", "extensions.json"])
  end

  defp update_file({:open_file, {:ok, file}}, app_info, exist_json) do
    with {:decode, {:ok, exist_json_data}} <- {:decode, Jason.decode(exist_json)},
         map_app_info <- [Map.from_struct(app_info)],
         {:encode, {:ok, new_apps}} <- {:encode, Jason.encode(exist_json_data ++ map_app_info)} do
          IO.binwrite(file, new_apps)
    else
      {:decode, {:error, _error}} ->
        {:error, :add_new_app, "We can not decode the JSON file, because this file has syntax problems. Please delete this file or fix it"}
      {:encode, {:error, _error}} -> {:error, :add_new_app, "We can not encode your new app data, please check your data."}
    end
  end

  defp update_file({:open_file, {:error, _posix}}, _app_info, _exist_json), do:
                  {:error, :add_new_app, "Unfortunately, the JSON concerned file either does not exist or we do not have access to it.
                  You can delete or create it in your panel, but before that please check you have enough access to edit it."}
end
