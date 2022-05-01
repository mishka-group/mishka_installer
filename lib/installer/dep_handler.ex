defmodule MishkaInstaller.Installer.DepHandler do
  alias MishkaInstaller.Reference.OnChangeDependency
  @event "on_change_dependency"
  defstruct [:app, :version, :type, :url, :git_tag, :timeout, :dependency_type, :update_server, dependencies: []]
  @moduledoc """

  A module that holds new dependencies' information, and add them into database or validating to implement in runtime

  ### Responsibilities of this module

  * Create `Json` - it helps developer to implement theire plugin/commponent into the project.
  * Add dependencies into database - for validating, stroing and keeping backup of runtime dependencies
  * Get dependencies information in several different ways


  ### For example, these are output from `Json` file
  ```elixir
  [
    %{
      app: :mishka_installer,
      version: "0.0.2",
      type: :git, # :hex, if user upload elixir libraries (path), we should keep them in a temporary folder, and Docker should make it valume
      url: "https://github.com/mishka-group/mishka_installer", # if it is hex: https://hex.pm/packages/mishka_installer
      git_tag: "0.0.2", # we consider it when it is a git, and if does not exist we get master,
      timeout: 3000, # it can be a feature, How long does it take to start?
      dependency_type: :none, # :soft_update, When you use this, the RunTime sourcing check what dependencies you use in your program have a higher version
      #compared to the old source. it just notice admin there is a update, it does not force the source to be updated
      dependencies: [ # this part let mishka_installer to know can update or not dependencies of a app, we should consider a backup file
        %{app: :mishka_developer_tools, max: "0.0.2", min: "0.0.1"},
        %{app: :mishka_social, max: "0.0.2", min: "0.0.1"}
      ],
      update_server: "https://github.com/mishka-group/mishka_installer/blob/master/update.json", # Check is there a higher version?
    }
  ]
  ```
  OR

  ```elixir
  %MishkaInstaller.Installer.DepHandler{
    app: "mishka_social",
    version: "0.0.2 ",
    type: "hex",
    url: "https://hex.pm/packages/mishka_social",
    git_tag: nil,
    timeout: nil,
    dependency_type: "soft_update",
    update_server: nil,
    dependencies: [
      %{app: :phoenix, min: "1.6"},
      %{app: :phoenix_live_view, max: "0.17.7", min: "0.17.7"},
      %{app: :ueberauth, max: "0.17.7", min: "0.17.7"},
      %{app: :ueberauth_github, min: "0.8.1"},
      %{app: :ueberauth_google, min: "0.10.1"},
    ]
  }
  ```
  """
  # TODO: if the application we want to added has migration what we should to do?

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

  @type installed_apps() :: {atom, description :: charlist(), vsn :: charlist()}

  # This function helps developer to decide what they should do when an app is going to be updated.
  # For example, each of the extensions maybe have states or necessary jobs, hence they can register their app for `on_change_dependency` event.
  @spec dependency_changes_notifier(atom(), atom()) :: any
  def dependency_changes_notifier(app, status \\ :soft_update) do
    case MishkaInstaller.PluginState.get_all(event: @event) do
      [] ->
        {:ok, :dependency_changes_notifier, :no_state, "We could not find any registered-app that has important state, hence you can update safely."}
      _value ->
        MishkaInstaller.Hook.call(event: @event, state: %OnChangeDependency{app: app, status: status}, operation: :no_return)
        # TODO: store {app, status, time} in `MishkaInstaller.Installer.DepChangesProtector`
        # TODO: MishkaInstaller.Installer.DepChangesProtector.push(app, status)
        {:ok, :dependency_changes_notifier, :registered_app,
        "There is an important state for an app at least, so we sent a notification to them and put your request in the update queue.
         After their response, we will change the #{app} dependency and let you know about its latest news."}
    end
  end

  def mix_read_from_json() do
    # TODO: Convert mix deps from json file
  end

  @spec compare_dependencies_with_json(installed_apps()| any()) :: list | {:error, :compare_dependencies_with_json, String.t()}
  def compare_dependencies_with_json(installed_apps \\ Application.loaded_applications) do
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:ok, json_data} <- Jason.decode(exist_json)do

        installed_apps = Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)
        Enum.map(json_data, fn app ->
          case Map.fetch(installed_apps, app["app"]) do
            :error -> nil
            {:ok, {installed_app, _des, installed_version}} ->
              %{
                app: installed_app,
                json_version: app["version"],
                installed_version: installed_version,
                status: Version.compare(String.trim(app["version"]), "#{installed_version}")
              }
          end
        end)
        |> Enum.reject(& is_nil(&1))
    else
      {:error, :check_or_create_deps_json, msg} -> {:error, :compare_dependencies_with_json, msg}
      {:error, %Jason.DecodeError{}} -> {:error, :compare_dependencies_with_json, "invalid Json file"}
    end
  end


  def compare_sub_dependencies_with_json(installed_apps \\ Application.loaded_applications) do
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:ok, json_data} <- Jason.decode(exist_json)do

      installed_apps = Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)
      Enum.map(merge_json_by_min_version(json_data), fn app ->
        case Map.fetch(installed_apps, app["app"]) do
          :error -> nil
          {:ok, {installed_app, _des, installed_version}} ->
            %{
              app: installed_app,
              json_min_version: app["min"],
              json_max_version: app["max"],
              installed_version: installed_version,
              min_status: Version.compare(String.trim(app["min"]), "#{installed_version}"),
              max_status: Version.compare(String.trim(app["max"]), "#{installed_version}")
            }
        end
      end)
      |> Enum.reject(& is_nil(&1))
    else
      {:error, :check_or_create_deps_json, msg} -> {:error, :compare_sub_dependencies_with_json, msg}
      {:error, %Jason.DecodeError{}} -> {:error, :compare_sub_dependencies_with_json, "invalid Json file"}
    end
  end

  @spec add_new_app(MishkaInstaller.Installer.DepHandler.t()) :: :ok | {:error, atom} | {:error, :add_new_app, String.t()}
  def add_new_app(%__MODULE__{} = app_info) do
    case check_or_create_deps_json() do
      {:ok, :check_or_create_deps_json, exist_json} ->
        insert_new_ap({:open_file, File.open(extensions_json_path(), [:read, :write])}, app_info, exist_json)
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
    {:ok, :read_dep_json, File.read!(extensions_json_path()) |> Jason.decode!()}
  rescue
    _e -> {:error, :read_dep_json, "You do not have access to read this file or maybe the file does not exist or even has syntax error"}
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

  # Ref: https://elixirforum.com/t/how-to-improve-sort-of-maps-in-a-list-which-have-duplicate-key/47486
  defp merge_json_by_min_version(json_data) do
    Enum.flat_map(json_data, &(&1["dependencies"]))
      |> Enum.group_by(&(&1["app"]))
      |> Enum.map(fn {_key, list} ->
        Enum.max_by(list, &(&1["min"]), Version)
      end)
  end

  defp insert_new_ap({:open_file, {:ok, file}}, app_info, exist_json) do
    with {:decode, {:ok, exist_json_data}} <- {:decode, Jason.decode(exist_json)},
         {:duplicate_app, false} <- {:duplicate_app, Enum.any?(exist_json_data, &(&1["app"] == Map.get(app_info, :app) || Map.get(app_info, "app")))},
         map_app_info <- [Map.from_struct(app_info)],
         {:encode, {:ok, new_apps}} <- {:encode, Jason.encode(exist_json_data ++ map_app_info)},
         {:ok, :add, :dependency, repo_data} <- MishkaInstaller.Dependency.create(Map.from_struct(app_info)) do
          IO.binwrite(file, new_apps)
          {:ok, :add_new_app, repo_data}
    else
      {:decode, {:error, _error}} ->
        {:error, :add_new_app, :file, "We can not decode the JSON file, because this file has syntax problems. Please delete this file or fix it"}
      {:duplicate_app, true} ->
        {:error, :add_new_app, :file, "You can not insert new app which is duplicate, if you want to update it please user another function."}
      {:encode, {:error, _error}} -> {:error, :add_new_app, :file, "We can not encode your new app data, please check your data."}
      {:error, :add, :dependency, repo_error} -> {:error, :add_new_app, :changeset, repo_error}
    end
  end

  defp insert_new_ap({:open_file, {:error, _posix}}, _app_info, _exist_json), do:
                  {:error, :add_new_app, :file, "Unfortunately, the JSON concerned file either does not exist or we do not have access to it.
                  You can delete or create it in your panel, but before that please check you have enough access to edit it."}
end
