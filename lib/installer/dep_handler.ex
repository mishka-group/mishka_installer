defmodule MishkaInstaller.Installer.DepHandler do
  @moduledoc """
  A module aggregates several operational functions to simplify the integration of all activities,
  including adding - removing, and updating a library in the project.
  For this purpose, you can use this module directly in your program or just call some helper functions.
  It should be noted that this module, like the `MishkaInstaller.Installer.RunTimeSourcing` module,
  has a primary function that performs all the mentioned operations based on the request type (`run/2`).
  Also, to perform some activities before applying any changes, the database and `extensions.json` file of your project will be rechecked.

  ### For example, these are output from `Json` file and this module struct
  ```elixir
  [
    %{
      app: :mishka_installer,
      version: "0.0.2",
      type: :git, # :hex, if user upload elixir libraries (path), we should keep them in a temporary folder, and Docker should make it valume
      url: "https://github.com/mishka-group/mishka_installer", # if it is hex: https://hex.pm/packages/mishka_installer
      git_tag: "0.0.2", # we consider it when it is a git, and if does not exist we get master,
      custom_command: "ecto.migrate", # you can write nil or you task file like ecto.migrate
      dependency_type: :none, # :force_update, When you use this, the RunTime sourcing check what dependencies you use
      # in your program have a higher version compared to the old source. it just notice admin there is a update,
      # it does not force the source to be updated.
      dependencies: [ # this part let mishka_installer to know can update or not dependencies of a app, we should consider a backup file
        %{app: :mishka_developer_tools, max: "0.0.2", min: "0.0.1"},
        %{app: :mishka_social, max: "0.0.2", min: "0.0.1"}
      ]
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
    dependencies: [
      %{app: :phoenix, min: "1.6"},
      %{app: :phoenix_live_view, max: "0.17.7", min: "0.17.7"},
      %{app: :ueberauth, max: "0.17.7", min: "0.17.7"},
      %{app: :ueberauth_github, min: "0.8.1"},
      %{app: :ueberauth_google, min: "0.10.1"},
    ]
  }
  ```

  ---

  ### Below you can see the graph of connecting this module to another module.

  ```
  +----------------------------+          +-------------------------------------+
  |                            |          |                                     |
  | MishkaInstaller.Dependency |          | MishkaInstaller.Installer.MixCreator|
  |                            <---+ +---->                                     |
  +----------------------------+   | |    +-------------------------------------+
                                   | |
                                   | |    +-----------------------------------------+
                                   | |    |                                         |
                                   | |    |MishkaInstaller.Installer.RunTimeSourcing|
                                   | |    |                                         |
                                   | |    +---^-------------------------------------+
                                   | |        |
  +--------------------------------+-+---+    |
  |                                      |    |
  | MishkaInstaller.Installer.DepHandler +----+
  |                                      |
  +----------------------------^---------+
                               |
                               |
      +------------------------+---------------+
      |                                        |
      |MishkaInstaller.Installer.Live.DepGetter|
      |                                        |
      +----------------------------------------+
  ```
  """

  @event "on_change_dependency"
  alias MishkaInstaller.{
    Dependency,
    Installer.MixCreator,
    Installer.DepChangesProtector,
    Installer.RunTimeSourcing
  }

  alias MishkaInstaller.Helper.Extra
  require Logger

  defstruct [
    :app,
    :version,
    :type,
    :url,
    :git_tag,
    :custom_command,
    :dependency_type,
    dependencies: []
  ]

  @typedoc "This type can be used when you want to introduce an app to install"
  @type app_info() :: String.t() | atom() | map() | list()
  @typedoc "This type can be used when you want to introduce method of install a dependency"
  @type run() :: :hex | :git | :upload
  @typedoc "This is delegate of `Application.loaded_applications/0` output"
  @type installed_apps() :: {atom, description :: charlist(), vsn :: charlist()}
  @typedoc "This type can be used when you want to put your data in this module struct"
  @type t() :: %__MODULE__{
          app: String.t() | nil,
          version: String.t() | nil,
          type: String.t() | nil,
          url: String.t() | nil,
          git_tag: String.t() | nil,
          custom_command: String.t() | nil,
          dependency_type: String.t() | nil,
          dependencies: [map()]
        }

  @doc """
  The `run/2` function is actually the function of the installer and assembler of all the modules that this module is connected to.
  This function has two inputs that you can see in the examples below. The first input is an atom, which specifies how to install a
  library in the system.
  Depending on the installation method, the second entry can be the dependency information requested for the installation.

  ## Examples

  ```elixir
  Application.spec(:timex, :vsn)

  MishkaInstaller.Installer.DepHandler.run(:hex, "faker")

  app = %{url: "https://github.com/bitwalker/timex", tag: "3.7.5"}
  MishkaInstaller.Installer.DepHandler.run(:git, app)

  app = %{url: "https://github.com/bitwalker/timex", tag: "3.7.6"}
  MishkaInstaller.Installer.DepHandler.run(:git, app)

  app = %{url: "https://github.com/bitwalker/timex", tag: "3.7.8"}
  MishkaInstaller.Installer.DepHandler.run(:git, app)


  app = %{url: "https://github.com/elixirs/faker", tag: "v0.17.0"}
  MishkaInstaller.Installer.DepHandler.run(:git, app)

  app = %{url: "https://github.com/martinsvalin/html_entities", tag: "v0.5.1"}
  MishkaInstaller.Installer.DepHandler.run(:git, app)


  app = %{url: "https://github.com/beatrichartz/csv", tag: "v2.3.0"}
  MishkaInstaller.Installer.DepHandler.run(:git, app)

  MishkaInstaller.Installer.DepHandler.run(:upload, ["../mishka_installer/deployment/extensions/timex-3.7.8.zip"])
  ```


  ### Reference

  - Fix phoenix reload issue when a dependency is compiled (https://github.com/phoenixframework/phoenix/issues/4278)
  - `Phoenix.CodeReloader.reload/1` (https://hexdocs.pm/phoenix/Phoenix.CodeReloader.html#reload/1)
  """

  @spec run(:git | :hex | :upload, app_info(), atom()) :: map()
  def run(type, app, output_type \\ :cmd)

  def run(:hex = type, app, output_type) do
    MishkaInstaller.Helper.Sender.package("hex", %{"app" => app})
    |> check_app_status(type, nil)
    |> run_request_handler(type, output_type)
  end

  def run(:git = type, app, output_type) do
    MishkaInstaller.Helper.Sender.package("github", %{"url" => app.url, "tag" => app.tag})
    |> check_app_status(type, nil)
    |> run_request_handler(type, output_type)
  end

  def run(:upload = type, [file_path], output_type) do
    unzip_dep_folder(file_path)
    |> check_mix_file_and_get_ast(file_path)
    |> check_app_status(:upload, file_path)
    |> run_request_handler(type, output_type)
  end

  @doc """
  This function provides an option to edit and start compiling from a `mix.exs` file.
  It should be considered to use this facility as a helper because it might be deleted on the next version from our primary process;
  `create_mix_file_and_start_compile/2` is kept to let developers use this based on their problems.
  You must put two entries, the first one is the app name, and the second one is the type of compiling, which can be shown in a terminal
  as stream outputs or sent with `Pubsub` and `Port`.
  This function is based on the `Sourceror` library, and the types we discussed include `:cmd` and `:port`.

  ### This function calls 3 other functions including:

  1. `create_deps_json_file/1`
  2. `MishkaInstaller.Installer.MixCreator.backup_mix/1`
  3. `MishkaInstaller.Installer.DepChangesProtector.deps/2`

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.create_mix_file_and_start_compile(app, type)
  ```
  """
  @spec create_mix_file_and_start_compile(String.t() | atom(), atom()) :: :ok
  def create_mix_file_and_start_compile(app_name, output_type) do
    mix_path = MishkaInstaller.get_config(:mix_path)
    MixCreator.backup_mix(mix_path)
    create_deps_json_file(MishkaInstaller.get_config(:project_path))

    list_json_dpes =
      Enum.map(mix_read_from_json(), fn {key, _v} ->
        String.contains?(File.read!(mix_path), "#{key}")
      end)
      |> Enum.any?(&(!&1))

    MixCreator.create_mix(MishkaInstaller.get_config(:mix).project[:deps], mix_path)

    if list_json_dpes do
      Logger.warn("Try to re-create Mix file")
      create_mix_file_and_start_compile(app_name, output_type)
    else
      DepChangesProtector.deps(app_name, output_type)
    end
  end

  @doc """
  For more information, please read `create_mix_file_and_start_compile/2`, but consider this function just
  re-creates `mix.exs` file and does not compile an app. This function is based on the `Sourceror` library.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.create_mix_file()
  ```
  """
  @spec create_mix_file :: :ok
  def create_mix_file() do
    mix_path = MishkaInstaller.get_config(:mix_path)
    create_deps_json_file(MishkaInstaller.get_config(:project_path))

    list_json_dpes =
      Enum.map(mix_read_from_json(), fn {key, _v} ->
        String.contains?(File.read!(mix_path), "#{key}")
      end)
      |> Enum.any?(&(!&1))

    MixCreator.create_mix(MishkaInstaller.get_config(:mix).project[:deps], mix_path)

    if list_json_dpes do
      Logger.warn("Try to re-create Mix file")
      create_mix_file()
    else
      :ok
    end
  end

  @doc """
  This function helps developers to decide what they should do when an app is going to be updated.
  For example, each of the extensions maybe has states or necessary jobs; hence they can register their app for `on_change_dependency` event.

  ## Examples

  ```
  old_ueberauth = %DepHandler{
    app: "ueberauth",
    version: "0.6.3",
    type: "hex",
    url: "https://hex.pm/packages/ueberauth",
    git_tag: nil,
    custom_command: nil,
    dependency_type: "force_update",
    dependencies: [
      %{app: :plug, min: "1.5.0"}
    ]
  }
  MishkaInstaller.Installer.DepHandler.add_new_app(old_ueberauth)
  ```
  """
  @spec add_new_app(MishkaInstaller.Installer.DepHandler.t()) ::
          {:ok, :add_new_app, any} | {:error, :add_new_app, :changeset | :file, any}
  def add_new_app(%__MODULE__{} = app_info) do
    case check_or_create_deps_json() do
      {:ok, :check_or_create_deps_json, exist_json} ->
        insert_new_ap(
          {:open_file, File.open(extensions_json_path(), [:read, :write])},
          app_info,
          exist_json
        )

      {:error, :check_or_create_deps_json, msg} ->
        {:error, :add_new_app, :file, msg}
    end
  end

  @doc """
  This Function is for interacting with the external `extensions.json` file to load added-libraries.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.read_dep_json()
  # or
  MishkaInstaller.Installer.DepHandler.mix_read_from_json(JSON_PATH)
  ```
  """
  @spec read_dep_json(any) :: {:error, :read_dep_json, String.t()} | {:ok, :read_dep_json, list()}
  def read_dep_json(json \\ File.read!(extensions_json_path())) do
    {:ok, :read_dep_json, json |> Jason.decode!()}
  rescue
    _e ->
      {:error, :read_dep_json,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "You do not have access to read this file or maybe the file does not exist or even has syntax error"
       )}
  end

  @doc """
  This function uses `read_dep_json/0` to read `extensions.json` file and returns list of dependencies-map.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.mix_read_from_json()
  ```
  """
  @spec mix_read_from_json :: list
  def mix_read_from_json() do
    case read_dep_json() do
      {:ok, :read_dep_json, data} ->
        Enum.map(data, fn item -> mix_creator(item["type"], item) end)

      {:error, :read_dep_json, msg} ->
        raise msg <> ". To make sure, re-create the JSON file from scratch."
    end
  end

  @doc """
  This function mixes your current list of dependencies with your added-dependencies from `extensions.json`.

  ### This function calls 1 other function including:

  1. `mix_read_from_json/0`

  ## Examples

  ```elixir
  list_of_deps =
    [
      {:finch, "~> 0.12.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:ueberauth, git: "url", tag: "0.6.3"}
    ]
  MishkaInstaller.Installer.DepHandler.append_mix(list_of_deps)
  ```
  """
  @spec append_mix([tuple()]) :: list
  def append_mix(list) do
    new_list = Enum.map(list, &(&1 |> Tuple.to_list() |> List.first()))

    json_mix =
      Enum.map(mix_read_from_json(), &mix_item(&1, new_list, list))
      |> Enum.reject(&is_nil(&1))

    Enum.reject(list, fn item ->
      List.first(Tuple.to_list(item)) in Enum.map(json_mix, fn item ->
        List.first(Tuple.to_list(item))
      end)
    end) ++ json_mix
  rescue
    _e -> list
  end

  @doc """
  A function to compare dependencies between `extensions.json` and `Application.loaded_applications/0`; if an app exists, it returns.


  ### This function calls 3 other functions including:

  1. `check_or_create_deps_json/0`
  2. `Application.loaded_applications/0`
  3. `read_dep_json/1`


  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.compare_dependencies_with_json()
  ```
  """
  @spec compare_dependencies_with_json(installed_apps() | any()) ::
          list | {:error, :compare_dependencies_with_json, String.t()}
  def compare_dependencies_with_json(installed_apps \\ Application.loaded_applications()) do
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:ok, :read_dep_json, json_data} <- read_dep_json(exist_json) do
      installed_apps =
        Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)

      Enum.map(json_data, fn app ->
        case Map.fetch(installed_apps, app["app"]) do
          :error ->
            nil

          {:ok, {installed_app, _des, installed_version}} ->
            %{
              app: installed_app,
              json_version: app["version"],
              installed_version: installed_version,
              status: Version.compare(String.trim(app["version"]), "#{installed_version}")
            }
        end
      end)
      |> Enum.reject(&is_nil(&1))
    else
      {:error, :check_or_create_deps_json, msg} -> {:error, :compare_dependencies_with_json, msg}
      _ -> {:error, :compare_dependencies_with_json, "invalid Json file"}
    end
  end

  @doc """
  This function works like `compare_dependencies_with_json/0`, but there is a difference which is in this part of the code,
  we compare the installed app with sup-dependencies based on min and max versions that are allowed.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.compare_sub_dependencies_with_json()
  ```

  ### Reference

  - How to improve sort of maps in a list which have duplicate key (https://elixirforum.com/t/47486)
  """
  @spec compare_sub_dependencies_with_json(any) ::
          list | {:error, :compare_sub_dependencies_with_json, String.t()}
  def compare_sub_dependencies_with_json(installed_apps \\ Application.loaded_applications()) do
    with {:ok, :check_or_create_deps_json, exist_json} <- check_or_create_deps_json(),
         {:ok, :read_dep_json, json_data} <- read_dep_json(exist_json) do
      installed_apps =
        Map.new(installed_apps, fn {app, _des, _ver} = item -> {Atom.to_string(app), item} end)

      Enum.map(merge_json_by_min_version(json_data), fn app ->
        case Map.fetch(installed_apps, app["app"]) do
          :error ->
            nil

          {:ok, {installed_app, _des, installed_version}} ->
            %{
              app: installed_app,
              json_min_version: app["min"],
              json_max_version: app["max"],
              installed_version: installed_version,
              min_status:
                if(!is_nil(app["min"]),
                  do: Version.compare(String.trim(app["min"]), "#{installed_version}"),
                  else: nil
                ),
              max_status:
                if(!is_nil(app["max"]),
                  do: Version.compare(String.trim(app["max"]), "#{installed_version}"),
                  else: nil
                )
            }
        end
      end)
      |> Enum.reject(&is_nil(&1))
    else
      {:error, :check_or_create_deps_json, msg} ->
        {:error, :compare_sub_dependencies_with_json, msg}

      _ ->
        {:error, :compare_sub_dependencies_with_json, "invalid Json file"}
    end
  end

  # TODO: it needs to use reverse with output to be improved like `MishkaInstaller.Installer.RunTimeSourcing.do_deps_compile` function.
  @doc """
  With this function, you can check and create `extensions.json` and its path.

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.check_or_create_deps_json()
  ```
  """
  @spec check_or_create_deps_json(binary) ::
          {:ok, :check_or_create_deps_json, String.t()}
          | {:error, :check_or_create_deps_json, String.t()}
  def check_or_create_deps_json(project_path \\ MishkaInstaller.get_config(:project_path)) do
    with {:deployment_path, true} <-
           {:deployment_path, File.exists?(Path.join(project_path, ["deployment"]))},
         {:extensions_path, true} <-
           {:extensions_path,
            File.exists?(Path.join(project_path, ["deployment/", "extensions"]))},
         {:json_file, true} <- {:json_file, File.exists?(extensions_json_path())},
         {:empty_json, true, json_data} <-
           {:empty_json, File.read!(extensions_json_path()) != "",
            File.read!(extensions_json_path())},
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

  @doc """
  It returns dependencies as a list of maps from `mix.exs`

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.get_deps_from_mix(MishkaInstaller.MixProject)
  ```
  """
  @spec get_deps_from_mix(module()) :: list
  def get_deps_from_mix(mix_module) do
    [{:deps, app_info} | _t] =
      Keyword.filter(mix_module.project, fn {key, _value} -> key == :deps end)

    Enum.map(app_info, fn app_info ->
      [app, version] = Tuple.to_list(app_info) |> Enum.take(2)
      %{app: app, version: version}
    end)
  end

  @doc """
  It returns dependencies as a list of maps from `mix.lock`, based on `Mix.Dep.Lock.read`

  ## Examples
  ```elixir
  MishkaInstaller.Installer.DepHandler.get_deps_from_mix_lock()
  ```
  """
  @spec get_deps_from_mix_lock :: list
  def get_deps_from_mix_lock() do
    Mix.Dep.Lock.read()
    |> Map.to_list()
    |> Enum.map(fn {key, list} ->
      [_h | [_app, version]] = Tuple.to_list(list) |> Enum.take(3)
      %{app: key, version: version}
    end)
  end

  @doc """
  This functions returns `extensions.json` file path based on `:project_path`.

  ## Examples
  ```elixir
  MishkaInstaller.Installer.DepHandler.extensions_json_path()
  ```
  """
  @spec extensions_json_path :: binary()
  def extensions_json_path() do
    path = MishkaInstaller.get_config(:project_path)
    Path.join(path, ["deployment/", "extensions/", "extensions.json"])
  end

  @doc """
  This function creates `extensions.json` as a json file.

  ## Examples
  ```elixir
  MishkaInstaller.Installer.DepHandler.create_deps_json_file(project_path)
  ```
  """
  @spec create_deps_json_file(binary()) ::
          {:error, :check_or_create_deps_json, binary} | {:ok, :check_or_create_deps_json, binary}
  def create_deps_json_file(project_path) do
    case File.open(extensions_json_path(), [:write]) do
      {:ok, file} ->
        IO.binwrite(file, Jason.encode!(MishkaInstaller.Dependency.dependencies()))
        File.close(file)
        check_or_create_deps_json(project_path)

      _error ->
        {:error, :check_or_create_deps_json,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "You do not have sufficient access to create this file. Please add it manually."
         )}
    end
  end

  @doc """
  This function compare installed app based on their files in `_build` and `deps` directory.

  ### This function calls 4 other functions including:

  1. `MishkaInstaller.Installer.RunTimeSourcing.read_app/2`
  2. `MishkaInstaller.Installer.RunTimeSourcing.consult_app_file/1`
  3. `compare_version_with_installed_app/2`
  4. `File.dir?/1`

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.compare_installed_deps_with_app_file("app_name")
  ```
  """
  @spec compare_installed_deps_with_app_file(String.t()) ::
          {:error, :compare_installed_deps_with_app_file, String.t()}
          | {:ok, :compare_installed_deps_with_app_file, list()}
  def compare_installed_deps_with_app_file(app) do
    new_app_path = Path.join(MishkaInstaller.get_config(:project_path), ["deps/", "#{app}"])

    if File.dir?(new_app_path) and File.dir?(new_app_path <> "/_build/#{Mix.env()}/lib") do
      apps_list =
        File.ls!(new_app_path <> "/_build/#{Mix.env()}/lib")
        |> Enum.map(fn sub_app ->
          with {:ok, bin} <- RunTimeSourcing.read_app(new_app_path, sub_app),
               {:ok, {:application, _, properties}} <- RunTimeSourcing.consult_app_file(bin),
               true <- compare_version_with_installed_app(sub_app, properties[:vsn]) do
            {sub_app, new_app_path <> "/_build/#{Mix.env()}/lib/#{sub_app}"}
          else
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil(&1))

      {:ok, :compare_installed_deps_with_app_file, apps_list}
    else
      {:error, :compare_installed_deps_with_app_file,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "App folder or its _build does not exist"
       )}
    end
  end

  @doc """
  With this function help you can move built app file to `_build` folder.

  ### This function calls 3 other functions including:

  1. `MishkaInstaller.Installer.RunTimeSourcing.do_runtime/2`
  2. `MishkaInstaller.Installer.RunTimeSourcing.get_build_path/0`
  3. `File.cp_r/3`

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.move_and_replace_compiled_app_build(app_list)
  ```
  """
  def move_and_replace_compiled_app_build(app_list) do
    Enum.map(app_list, fn {app, build_path} ->
      RunTimeSourcing.do_runtime(String.to_atom(app), :uninstall)
      File.cp_r(build_path, Path.join(RunTimeSourcing.get_build_path(), "#{app}"))
    end)
  end

  @doc """
  This function helps you to compare an app version with its installed version, it returns `true` or `false`.
  Based on `Application.spec/2`

  ## Examples

  ```elixir
  MishkaInstaller.Installer.DepHandler.compare_version_with_installed_app(app, version)
  ```
  """
  def compare_version_with_installed_app(app, version) do
    ver = Application.spec(String.to_atom(app), :vsn)
    if !is_nil(ver), do: Version.compare("#{version}", "#{ver}") == :gt, else: true
  end

  defp create_deps_json_directory(project_path, folder_path) do
    case File.mkdir(Path.join(project_path, folder_path)) do
      :ok ->
        check_or_create_deps_json(project_path)

      {:error, :eacces} ->
        {:error, :check_or_create_deps_json,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "You do not have sufficient access to create this directory. Please add it manually."
         )}

      {:error, :enospc} ->
        {:error, :check_or_create_deps_json,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "there is no space left on the device."
         )}

      {:error, e} when e in [:eexist, :enoent, :enotdir] ->
        {:error, :check_or_create_deps_json,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "Please contact plugin support when you encounter this error."
         )}
    end
  end

  # Ref: https://elixirforum.com/t/how-to-improve-sort-of-maps-in-a-list-which-have-duplicate-key/47486
  defp merge_json_by_min_version(json_data) do
    Enum.flat_map(json_data, & &1["dependencies"])
    |> Enum.group_by(& &1["app"])
    |> Enum.map(fn {_key, list} ->
      Enum.max_by(list, & &1["min"], Version)
    end)
  end

  defp insert_new_ap({:open_file, {:ok, _file}}, app_info, exist_json) do
    with {:decode, {:ok, exist_json_data}} <- {:decode, Jason.decode(exist_json)},
         {:duplicate_app, false} <-
           {:duplicate_app,
            Enum.any?(
              exist_json_data,
              &(&1["app"] == Map.get(app_info, :app) || Map.get(app_info, "app"))
            )},
         map_app_info <- [Map.from_struct(app_info)],
         {:encode, {:ok, _new_apps}} <- {:encode, Jason.encode(exist_json_data ++ map_app_info)},
         {:ok, :add, :dependency, repo_data} <-
           MishkaInstaller.Dependency.create(Map.from_struct(app_info)) do
      # after the new app added into the database, the DepChangesProtector module remove the json file and re-create it
      {:ok, :add_new_app, repo_data}
    else
      {:decode, {:error, _error}} ->
        {:error, :add_new_app, :file,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "We can not decode the JSON file, because this file has syntax problems. Please delete this file or fix it"
         )}

      {:duplicate_app, true} ->
        {:error, :add_new_app, :file,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "You can not insert new app which is duplicate, if you want to update it please use another function."
         )}

      {:encode, {:error, _error}} ->
        {:error, :add_new_app, :file,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "We can not encode your new app data, please check your data."
         )}

      {:error, :add, :dependency, repo_error} ->
        {:error, :add_new_app, :changeset, repo_error}
    end
  end

  defp insert_new_ap({:open_file, {:error, _posix}}, _app_info, _exist_json),
    do:
      {:error, :add_new_app, :file,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "Unfortunately, the JSON concerned file either does not exist or we do not have access to it. You can delete or create it in your panel, but before that please check you have enough access to edit it."
       )}

  defp mix_creator("hex", data) do
    {String.to_atom(data["app"]), "~> #{String.trim(data["version"])}"}
  end

  defp mix_creator("path", data) do
    uploaded_extension =
      Path.join(MishkaInstaller.get_config(:project_path), [
        "deployment/",
        "extensions/",
        "#{data["app"]}"
      ])

    {String.to_atom(data["app"]), path: uploaded_extension}
  end

  defp mix_creator("git", data) do
    case data["git_tag"] do
      nil ->
        {String.to_atom(data["app"]), git: data["url"]}

      _ ->
        {String.to_atom(data["app"]), git: data["url"], tag: data["git_tag"]}
    end
  end

  # The priority of path and git master/main are always higher the `mix` dependencies list.
  defp mix_item({_app, path: _uploaded_extension} = value, _app_list, _deps_list), do: value
  defp mix_item({_app, git: _url} = value, _app_list, _deps_list), do: value

  defp mix_item({app, git: _url, tag: imporetd_version} = value, app_list, deps_list) do
    if app in app_list,
      do: check_same_app_version(app, deps_list, imporetd_version, value),
      else: value
  end

  defp mix_item({app, imporetd_version} = value, app_list, deps_list) do
    if app in app_list,
      do: check_same_app_version(app, deps_list, imporetd_version, value),
      else: value
  end

  defp check_same_app_version(app, deps_list, imporetd_version, value) do
    founded_app =
      Enum.find(deps_list, fn item -> Enum.take(Tuple.to_list(item), 1) |> List.first() == app end)

    case Enum.take(Tuple.to_list(founded_app), 3) |> List.to_tuple() do
      {_founded_app_name, git: _url} ->
        nil

      {_founded_app_name, git: _url, tag: tag} ->
        if Version.compare(clean_mix_version(imporetd_version), clean_mix_version(tag)) in [
             :eq,
             :lt
           ],
           do: nil,
           else: value

      {_founded_app_name, version} ->
        if Version.compare(clean_mix_version(imporetd_version), clean_mix_version(version)) in [
             :eq,
             :lt
           ],
           do: nil,
           else: value
    end
  rescue
    _e -> nil
  end

  defp clean_mix_version(version) do
    version
    |> String.replace("~>", "")
    |> String.replace(">=", "")
    |> String.replace("v", "")
    |> String.trim()
  end

  defp check_app_status({:ok, :package, pkg}, :hex, _) do
    create_app_info(pkg, :hex)
    |> Map.from_struct()
    |> sync_app_with_database()
  end

  defp check_app_status(result, type, file_path) when type in [:git, :upload] do
    case result do
      {:error, :package, result} when result in [:mix_file, :not_found, :not_tag, :unhandled] ->
        {:error,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "Unfortunately, an error occurred while we were comparing your mix.exs file. The flag of erorr is %{result}",
           result: result
         )}

      data ->
        if Enum.any?(data, &(&1 == {:error, :package, :convert_ast_output})) do
          {:error,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "Your mix.exs file must contain the app, version and source_url parameters"
           )}
        else
          create_app_info(data, if(type == :git, do: type, else: :path))
          |> Map.from_struct()
          |> rename_folder_copy_to_deps(file_path)
          |> sync_app_with_database()
        end
    end
  end

  defp check_app_status({:error, :package, status}, type, _) do
    msg =
      if status == :not_found do
        Gettext.dgettext(
          MishkaInstaller.gettext(),
          "mishka_installer",
          "Are you sure you have entered the package name or url correctly?"
        )
      else
        Gettext.dgettext(
          MishkaInstaller.gettext(),
          "mishka_installer",
          "Unfortunately, we cannot connect to %{type} server now, please try other time! or make it correct",
          type: type
        )
      end

    {:error, msg}
  end

  defp rename_folder_copy_to_deps(data, file_path)
       when not is_nil(file_path) and is_binary(file_path) do
    file =
      Path.join(MishkaInstaller.get_config(:project_path), [
        "deployment/",
        "extensions/",
        "#{Path.basename(file_path, ".zip")}"
      ])

    new_name =
      Path.join(MishkaInstaller.get_config(:project_path), [
        "deployment/",
        "extensions/",
        "#{data.app}"
      ])

    File.rename!(file, new_name)

    File.cp_r!(
      new_name,
      Path.join(MishkaInstaller.get_config(:project_path), ["deps/", "#{data.app}"])
    )

    data
  end

  defp rename_folder_copy_to_deps(data, _file_path), do: data

  defp sync_app_with_database(data) do
    if compare_version_with_installed_app(data.app, data.version) do
      case Dependency.create_or_update(data) do
        {:ok, :add, :dependency, repo_data} ->
          {:ok, :no_state,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "We could not find any registered-app that has important state, hence you can update safely. It should be noted if you send multi apps before finishing previous app, other new apps are saved in a queue."
           ), repo_data.app}

        {:ok, :edit, :dependency, repo_data} ->
          if MishkaInstaller.PluginETS.get_all(event: @event) == [] do
            {:ok, :no_state,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "We could not find any registered-app that has important state, hence you can update safely. It should be noted if you send multi apps before finishing previous app, other new apps are saved in a queue."
             ), repo_data.app}
          else
            {:ok, :registered_app,
             Gettext.dgettext(
               MishkaInstaller.gettext(),
               "mishka_installer",
               "There is an important state for an app at least, so we sent a notification to them and put your request in the update queue. After their response, we will change the %{app} dependency and let you know about its latest news.",
               app: repo_data.app
             ), repo_data.app}
          end

        {:error, action, :dependency, _repo_error} when action in [:add, :edit] ->
          # TODO: save it in activities
          {:error,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "Unfortunately, an error occurred while storing the data in the database. To check for errors, see the Activities section, and if this error persists, report it to support."
           )}

        {:error, action, :uuid, _error_tag} when action in [:uuid, :get_record_by_id] ->
          # TODO: save it in activities
          {:error,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "Unfortunately, an error occurred while storing the data in the database. To check for errors, see the Activities section, and if this error persists, report it to support."
           )}

        {:error, :update_app_version, :older_version} ->
          {:error,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "You have already installed this library and the installed version is the same as the latest version of the Hex site. Please take action when a new version of this app is released"
           )}
      end
    else
      {:error,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "You have already installed this library and the installed version is the same as the latest version of the Hex site. Please take action when a new version of this app is released"
       )}
    end
  end

  defp run_request_handler(status, type, output_type) do
    case status do
      {:ok, :no_state, msg, app_name} ->
        MishkaInstaller.DepCompileJob.add_job(app_name, output_type)

        %{
          "app_name" => app_name,
          "status_message_type" => :success,
          "message" => msg,
          "selected_form" => type
        }

      {:ok, :registered_app, msg, app_name} ->
        %{
          "app_name" => app_name,
          "status_message_type" => :info,
          "message" => msg,
          "selected_form" => :registered_app
        }

      {:error, msg} ->
        %{
          "app_name" => nil,
          "status_message_type" => :danger,
          "message" => msg,
          "selected_form" => type
        }
    end
  end

  defp unzip_dep_folder(file_path) do
    {:unzip,
     :zip.unzip(~c'#{file_path}', [
       {:cwd,
        ~c'#{Path.join(MishkaInstaller.get_config(:project_path), ["deployment/", "extensions"])}'}
     ])}
  end

  defp check_mix_file_and_get_ast({:unzip, {:ok, _content}}, file_path) do
    mix_file =
      Path.join(MishkaInstaller.get_config(:project_path), [
        "deployment/",
        "extensions/",
        "#{Path.basename(file_path, ".zip")}",
        "/mix.exs"
      ])

    with {:mix_file, {:ok, body}} <- {:mix_file, File.read(mix_file)},
         {:code, {:ok, ast}} <- {:code, Code.string_to_quoted(body)} do
      Extra.ast_mix_file_basic_information(ast, [:app, :version, :source_url])
    else
      {:mix_file, {:error, _error}} -> {:error, :package, :mix_file}
      {:code, {:error, _error}} -> {:error, :package, :string_mix_file}
    end
  end

  defp check_mix_file_and_get_ast({:unzip, {:error, _error}}, _file_path),
    do: {:error, :package, :unzip}

  defp create_app_info(pkg, :hex) do
    %__MODULE__{
      app: pkg["name"],
      version: pkg["latest_stable_version"],
      type: "hex",
      url: pkg["html_url"],
      dependency_type: "force_update",
      dependencies: []
    }
  end

  defp create_app_info([app: app, version: version, source_url: source_url, tag: tag], :git) do
    %__MODULE__{
      app: "#{app}",
      version: "#{version}",
      type: "git",
      git_tag: tag,
      url: "#{source_url}",
      dependency_type: "force_update",
      dependencies: []
    }
  end

  defp create_app_info([app: app, version: version, source_url: source_url], :path) do
    %__MODULE__{
      app: "#{app}",
      version: "#{version}",
      type: "path",
      url: "#{source_url}",
      dependency_type: "force_update",
      dependencies: []
    }
  end
end
