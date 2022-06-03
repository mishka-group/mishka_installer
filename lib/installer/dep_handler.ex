defmodule MishkaInstaller.Installer.DepHandler do
  alias MishkaInstaller.Reference.OnChangeDependency
  @event "on_change_dependency"
  alias MishkaInstaller.{Dependency, Installer.MixCreator, Installer.DepChangesProtector}
  require Logger
  defstruct [:app, :version, :type, :url, :git_tag, :custom_command, :dependency_type, :update_server, dependencies: []]
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
      custom_command: "ecto.migrate", # you can write nil or you task file like ecto.migrate
      dependency_type: :none, # :force_update, When you use this, the RunTime sourcing check what dependencies you use in your program have a higher version
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
    custom_command: nil,
    dependency_type: "force_update",
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

  @type installed_apps() :: {atom, description :: charlist(), vsn :: charlist()}
  @type t() :: %__MODULE__{
    app: String.t() | nil,
    version: String.t() | nil,
    type: String.t() | nil,
    url: String.t() | nil,
    git_tag: String.t() | nil,
    custom_command: String.t() | nil,
    dependency_type: String.t() | nil,
    update_server: String.t() | nil,
    dependencies: [map()],
  }

  def run(:hex, app) do
    MishkaInstaller.Helper.Sender.package("hex", %{"app" => app})
    |> check_app_exist?(:hex)
    |> case do
      {:ok, :no_state, _msg, app_name, first_binding: first_binding} ->
        check_new_mix_file(app_name, first_binding)
      {:ok, :registered_app, _msg, _app_name, first_binding: _first_binding} -> {:ok, :registered_app}
      {:error, msg} ->  {:danger, msg}
    end
  end

  # This function helps developer to decide what they should do when an app is going to be updated.
  # For example, each of the extensions maybe have states or necessary jobs, hence they can register their app for `on_change_dependency` event.
  @spec add_new_app(MishkaInstaller.Installer.DepHandler.t()) ::
          {:ok, :add_new_app, any} | {:error, :add_new_app, :changeset | :file, any}
  def add_new_app(%__MODULE__{} = app_info) do
    case check_or_create_deps_json() do
      {:ok, :check_or_create_deps_json, exist_json} ->
        insert_new_ap({:open_file, File.open(extensions_json_path(), [:read, :write])}, app_info, exist_json)
      {:error, :check_or_create_deps_json, msg} -> {:error, :add_new_app, :file, msg}
    end
  end

  @spec read_dep_json(any) :: {:error, :read_dep_json, String.t()} | {:ok, :read_dep_json, list()}
  def read_dep_json(json \\ File.read!(extensions_json_path())) do
    {:ok, :read_dep_json, json |> Jason.decode!()}
  rescue
    _e -> {:error, :read_dep_json, "You do not have access to read this file or maybe the file does not exist or even has syntax error"}
  end

  @spec mix_read_from_json :: list
  def mix_read_from_json() do
    case read_dep_json() do
      {:ok, :read_dep_json, data} ->
        Enum.map(data, fn item -> mix_creator(item["type"], item) end)
      {:error, :read_dep_json, msg} ->
        raise msg <> ". To make sure, re-create the JSON file from scratch."
    end
  end

  @spec dependency_changes_notifier(String.t(), String.t()) ::
          {:error, :dependency_changes_notifier, String.t()}
          | {:ok, :dependency_changes_notifier, :no_state | :registered_app, String.t()}
  def dependency_changes_notifier(app, status \\ "force_update") do
    case MishkaInstaller.PluginState.get_all(event: @event) do
      [] ->
        update_app_status(app, status, :no_state)
      _value ->
        MishkaInstaller.Hook.call(event: @event, state: %OnChangeDependency{app: app, status: status}, operation: :no_return)
        update_app_status(app, status, :registered_app)
    end
  end

  @spec append_mix([tuple()]) :: list
  def append_mix(list) do
    new_list = Enum.map(list , &(&1 |> Tuple.to_list |> List.first()))
    json_mix =
      Enum.map(mix_read_from_json(), & mix_item(&1, new_list, list))
      |> Enum.reject(& is_nil(&1))
      Enum.reject(list, fn item ->
        (List.first(Tuple.to_list(item))) in Enum.map(json_mix, fn item -> List.first(Tuple.to_list(item)) end)
      end) ++ json_mix
  rescue
    _e -> list
  end

  @spec compare_dependencies_with_json(installed_apps()| any()) :: list | {:error, :compare_dependencies_with_json, String.t()}
  def compare_dependencies_with_json(installed_apps \\ Application.loaded_applications) do
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:ok, :read_dep_json, json_data} <- read_dep_json(exist_json) do

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
      _ -> {:error, :compare_dependencies_with_json, "invalid Json file"}
    end
  end

  @spec compare_sub_dependencies_with_json(any) :: list | {:error, :compare_sub_dependencies_with_json, String.t()}
  def compare_sub_dependencies_with_json(installed_apps \\ Application.loaded_applications) do
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:ok, :read_dep_json, json_data} <- read_dep_json(exist_json) do

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
              min_status: if(!is_nil(app["min"]), do: Version.compare(String.trim(app["min"]), "#{installed_version}"), else: nil),
              max_status: if(!is_nil(app["max"]), do: Version.compare(String.trim(app["max"]), "#{installed_version}"), else: nil)
            }
        end
      end)
      |> Enum.reject(& is_nil(&1))
    else
      {:error, :check_or_create_deps_json, msg} -> {:error, :compare_sub_dependencies_with_json, msg}
      _ -> {:error, :compare_sub_dependencies_with_json, "invalid Json file"}
    end
  end

  @spec check_or_create_deps_json(binary) :: {:ok, :check_or_create_deps_json, String.t()} | {:error, :check_or_create_deps_json, String.t()}
  def check_or_create_deps_json(project_path \\ (MishkaInstaller.get_config(:project_path) || File.cwd!())) do
    with {:deployment_path, true} <- {:deployment_path, File.exists?(Path.join(project_path, ["deployment"]))},
         {:extensions_path, true} <- {:extensions_path, File.exists?(Path.join(project_path, ["deployment/", "extensions"]))},
         {:json_file, true} <- {:json_file, File.exists?(extensions_json_path())},
         {:empty_json, true, json_data} <- {:empty_json, File.read!(extensions_json_path()) != "", File.read!(extensions_json_path())},
         {:ok, :read_dep_json, _converted_json} <- read_dep_json(json_data) do

         {:ok, :check_or_create_deps_json, json_data}
    else
      {:deployment_path, false} ->
        create_deps_json_directory(project_path, "deployment")
      {:extensions_path, false} ->
        create_deps_json_directory(project_path, "deployment/extensions")
      {:json_file, false} ->
        create_deps_json_file(project_path)
      {:empty_json, false, _data} ->
        File.rm_rf(extensions_json_path())
        create_deps_json_file(project_path)
      {:error, :read_dep_json, _msg} ->
        File.rm_rf(extensions_json_path())
        create_deps_json_file(project_path)
    end
  end

  @spec get_deps_from_mix(module()) :: list
  def get_deps_from_mix(mix_module) do
    [{:deps, app_info} | _t] = Keyword.filter(mix_module.project, fn {key, _value} -> key == :deps end)
    Enum.map(app_info, fn app_info ->
      [app, version] = Tuple.to_list(app_info) |> Enum.take(2)
      %{app: app, version: version}
    end)
  end

  @spec get_deps_from_mix_lock :: list
  def get_deps_from_mix_lock() do
    Mix.Dep.Lock.read
    |> Map.to_list()
    |> Enum.map(fn {key, list} ->
      [_h | [_app, version]] = Tuple.to_list(list) |> Enum.take(3)
      %{app: key, version: version}
    end)
  end

  @spec extensions_json_path :: binary()
  def extensions_json_path() do
    path = MishkaInstaller.get_config(:project_path) || File.cwd!()
    Path.join(path, ["deployment/", "extensions/", "extensions.json"])
  end

  @spec is_there_update? :: boolean
  def is_there_update?() do
    if length(MishkaInstaller.Installer.UpdateChecker.get()) == 0, do: false, else: true
  end

  @spec is_there_update?(String.t()) :: boolean
  def is_there_update?(app) do
    if is_nil(MishkaInstaller.Installer.UpdateChecker.get(app)), do: false, else: true
  end

  @spec create_deps_json_file(binary()) :: {:error, :check_or_create_deps_json, binary} | {:ok, :check_or_create_deps_json, binary}
  def create_deps_json_file(project_path) do
    case File.open(extensions_json_path(), [:write]) do
      {:ok, file} ->
        IO.binwrite(file, Jason.encode!(MishkaInstaller.Dependency.dependencies()))
        File.close(file)
        check_or_create_deps_json(project_path)
      _error -> {:error, :check_or_create_deps_json, "You do not have sufficient access to create this file. Please add it manually."}
    end
  end

  # Ref: https://elixirforum.com/t/how-to-get-vsn-from-app-file/48132/2
  # Ref: https://github.com/elixir-lang/elixir/blob/main/lib/mix/lib/mix/tasks/compile.all.ex#L153-L154
  @spec compare_installed_deps_with_app_file(String.t()) :: list | {:error, :compare_installed_deps_with_app_file, String.t()}
  def compare_installed_deps_with_app_file(app) do
    new_app_path = Path.join(MishkaInstaller.get_config(:project_path) || File.cwd!(), ["deps/", "#{app}"])
    if File.dir?(new_app_path) and File.dir?(new_app_path <> "/_build/#{Mix.env()}/lib") do
      File.ls!(new_app_path <> "/_build/#{Mix.env()}/lib")
      |> Enum.map(fn sub_app ->
        with {:ok, bin} <- read_app(new_app_path, sub_app) ,
             {:ok, {:application, _, properties}} <- consult_app_file(bin),
             true <- compare_version_of_file_and_installed_app(properties, sub_app),
             true <- sub_app != app do
              {sub_app, new_app_path <> "/_build/#{Mix.env()}/lib/#{sub_app}"}
        else
          _ -> nil
        end
      end)
      |> Enum.reject(& is_nil(&1))
    else
      {:error, :compare_installed_deps_with_app_file, "App folder or its _build does not exist"}
    end
  end

  defp compare_version_of_file_and_installed_app(file_properties, sub_app) do
    ver = Application.spec(String.to_atom(sub_app), :vsn)
    if !is_nil(ver) do
      Version.compare("#{file_properties[:vsn]}", "#{ver}") == :gt
    else
      true
    end
  end

  defp read_app(lib_path, sub_app) do
    File.read("#{lib_path}/_build/#{Mix.env()}/lib/#{sub_app}/ebin/#{sub_app}.app")
  end

  defp consult_app_file(bin) do
    # The path could be located in an .ez archive, so we use the prim loader.
    with {:ok, tokens, _} <- :erl_scan.string(String.to_charlist(bin)) do
      :erl_parse.parse_term(tokens)
    end
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

  # Ref: https://elixirforum.com/t/how-to-improve-sort-of-maps-in-a-list-which-have-duplicate-key/47486
  defp merge_json_by_min_version(json_data) do
    Enum.flat_map(json_data, &(&1["dependencies"]))
    |> Enum.group_by(&(&1["app"]))
    |> Enum.map(fn {_key, list} ->
      Enum.max_by(list, &(&1["min"]), Version)
    end)
  end

  defp insert_new_ap({:open_file, {:ok, _file}}, app_info, exist_json) do
    with {:decode, {:ok, exist_json_data}} <- {:decode, Jason.decode(exist_json)},
         {:duplicate_app, false} <- {:duplicate_app, Enum.any?(exist_json_data, &(&1["app"] == Map.get(app_info, :app) || Map.get(app_info, "app")))},
         map_app_info <- [Map.from_struct(app_info)],
         {:encode, {:ok, _new_apps}} <- {:encode, Jason.encode(exist_json_data ++ map_app_info)},
         {:ok, :add, :dependency, repo_data} <- MishkaInstaller.Dependency.create(Map.from_struct(app_info)) do
          # after the new app added into the database, the DepChangesProtector module remove the json file and re-create it
          {:ok, :add_new_app, repo_data}
    else
      {:decode, {:error, _error}} ->
        {:error, :add_new_app, :file, "We can not decode the JSON file, because this file has syntax problems. Please delete this file or fix it"}
      {:duplicate_app, true} ->
        {:error, :add_new_app, :file, "You can not insert new app which is duplicate, if you want to update it please use another function."}
      {:encode, {:error, _error}} -> {:error, :add_new_app, :file, "We can not encode your new app data, please check your data."}
      {:error, :add, :dependency, repo_error} -> {:error, :add_new_app, :changeset, repo_error}
    end
  end

  defp insert_new_ap({:open_file, {:error, _posix}}, _app_info, _exist_json), do:
                  {:error, :add_new_app, :file, "Unfortunately, the JSON concerned file either does not exist or we do not have access to it.
                  You can delete or create it in your panel, but before that please check you have enough access to edit it."}

  defp mix_creator("hex", data) do
    {String.to_atom(data["app"]), "~> #{String.trim(data["version"])}"}
  end

  defp mix_creator("upload", data) do
    uploaded_extension =
      Path.join(MishkaInstaller.get_config(:project_path) || File.cwd!(), ["deployment/", "extensions/", "#{data["app"]}"])
    {String.to_atom(data["app"]), path: uploaded_extension}
  end

  defp mix_creator("git", data) do
    case data["tag"] do
      nil ->
        {String.to_atom(data["app"]), git: data["url"]}
      _ ->
        {String.to_atom(data["app"]), git: data["url"], tag: data["tag"]}
    end
  end

  defp update_app_status(app, status, state) do
    with {:ok, :change_dependency_type_with_app, _repo_data} <- Dependency.change_dependency_type_with_app(app, status) do
         {:ok, :dependency_changes_notifier, state,
         if state == :no_state do
          "We could not find any registered-app that has important state, hence you can update safely."
         else
          "There is an important state for an app at least, so we sent a notification to them and put your request in the update queue.
          After their response, we will change the #{app} dependency and let you know about its latest news."
         end
      }
    else
      {:error, :change_dependency_type_with_app, :dependency, _error} ->
        {:error, :dependency_changes_notifier,
        "Unfortunately we couldn't find your app, if you did not submit the app you want to update please add it at first and send request to this app."}
    end
  end

  # The priority of path and git master/main are always higher the `mix` dependencies list.
  defp mix_item({_app, path: _uploaded_extension} = value, _app_list, _deps_list), do: value
  defp mix_item({_app, git: _url} = value, _app_list, _deps_list), do: value

  defp mix_item({app, git: _url, tag: imporetd_version} = value, app_list, deps_list) do
    if app in app_list, do: check_same_app_version(app, deps_list, imporetd_version, value), else: value
  end

  defp mix_item({app, imporetd_version} = value, app_list, deps_list) do
    if app in app_list, do: check_same_app_version(app, deps_list, imporetd_version, value), else: value
  end

  defp check_same_app_version(app, deps_list, imporetd_version, value) do
    founded_app = Enum.find(deps_list, fn item -> (Enum.take(Tuple.to_list(item), 1) |> List.first()) == app end)
    case Enum.take(Tuple.to_list(founded_app), 3) |> List.to_tuple do
      {_founded_app_name, git: _url} -> nil
      {_founded_app_name, git: _url, tag: tag} ->
        if Version.compare(clean_mix_version(imporetd_version), clean_mix_version(tag)) in [:eq, :lt], do: nil, else: value
      {_founded_app_name, version} ->
        if Version.compare(clean_mix_version(imporetd_version), clean_mix_version(version)) in [:eq, :lt], do: nil, else: value
    end
  end

  defp clean_mix_version(version) do
    version
    |> String.replace("~>", "")
    |> String.replace(">=", "")
    |> String.trim()
  end

  defp check_app_exist?({:ok, :package, pkg}, :hex) do
    json_find = fn (json, app_name) -> Enum.find(json, &(&1["app"] == app_name)) end
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:first_binding, true, nil} <- {:first_binding, is_nil(json_find.(Jason.decode!(exist_json), pkg["name"])), json_find.(Jason.decode!(exist_json), pkg["name"])},
         app_info <- create_app_info_from_hex(pkg),
         {:ok, :add_new_app, _repo_data} <- add_new_app(app_info),
         {:ok, :dependency_changes_notifier, :no_state, msg} <- dependency_changes_notifier(pkg["name"]) do
          {:ok, :no_state, msg, pkg["name"], first_binding: true}
    else
      {:first_binding, false, app} -> msg_of_exit_app(app, pkg)
      {:error, :check_or_create_deps_json, msg} -> {:error, msg}
      {:error, :add_new_app, :file, msg} -> {:error, msg}
      {:error, :add_new_app, :changeset, _repo_error} ->
        # TODO: log this error in activity section
        {:error, "This error occurs when you can not add a new plugin to the database. If repeated, please contact support."}
      {:error, :dependency_changes_notifier, msg} -> {:error, msg}
      {:ok, :dependency_changes_notifier, :registered_app, msg} -> {:ok, :registered_app, msg, first_binding: true}
    end
  end

  defp check_app_exist?({:error, :package, status}, _) do
    msg = if status == :not_found, do: "Are you sure you have entered the package name correctly?", else: "Unfortunately, we cannot connect to Hex server now, please try other time!"
    {:error, msg}
  end

  defp msg_of_exit_app(app, pkg) do
    if app["version"] == pkg["latest_stable_version"] do
      {:error, "You have already installed this library and the installed version is the same as the latest version of the Hex site. Please take action when a new version of this app is released"}
    else
      Dependency.update_app_version(app["app"], pkg["latest_stable_version"])
      case dependency_changes_notifier(pkg["name"]) do
        {:ok, :dependency_changes_notifier, :no_state, msg} -> {:ok, :no_state, msg, first_binding: false}
        {:ok, :dependency_changes_notifier, :registered_app, msg} -> {:ok, :registered_app, msg, pkg["name"], first_binding: false}
        {:error, :dependency_changes_notifier, msg} -> {:error, msg}
      end
    end
  end

  defp create_app_info_from_hex(pkg) do
    %__MODULE__{
      app: pkg["name"],
      version: pkg["latest_stable_version"],
      type: "hex",
      url: pkg["html_url"],
      dependency_type: "force_update",
      dependencies: []
    }
  end

  defp check_new_mix_file(app_name, first_binding) do
    mix_path = MishkaInstaller.get_config(:mix_path)
    list_json_dpes =
      Enum.map(mix_read_from_json(), fn {key, _v} -> String.contains?(File.read!(mix_path), "#{key}") end)
      |> Enum.any?(& !&1)

    MixCreator.create_mix(MishkaInstaller.get_config(:mix).project[:deps], mix_path)
    if list_json_dpes do
      Logger.warn("Try to re-create Mix file")
      check_new_mix_file(app_name, first_binding)
    else
      DepChangesProtector.deps(app_name, first_binding)
    end
  end
end
