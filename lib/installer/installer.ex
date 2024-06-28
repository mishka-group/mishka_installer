defmodule MishkaInstaller.Installer.Installer do
  @moduledoc """
  When it comes to `Erlan`g and `Elixir`, the process of runtime installing and runtime uninstalling a
  new library or runtime upgrading it is subject to a number of constraints.

  These restrictions can be implemented based on specific strategies and under specific conditions.

  Please take note that this is not about **hot coding**, which refers to the process of updating
  a module that was developed using `GenServer`.

  On account of this objective, a number of action functions have been incorporated into
  this module in order to make it possible for this task to be completed for you in
  accordance with some **established strategies**.

  Among these tactics is the utilisation of the `Mix` tool, which is located within
  the `System` and `Port` module.

  **During the subsequent releases, we will make an effort to incorporate the `script` mode**.
  - Based on: https://elixirforum.com/t/12114/14

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  > #### Use cases information {: .tip}
  >
  > Especially when you want to work with a library that depends on a large number
  > of other libraries or vice versa, each of the functions of this file has its own
  > requirements that must be taken into consideration.
  """
  use GuardedStruct
  alias MishkaDeveloperTools.Helper.{Extra, UUID}
  alias MishkaInstaller.Installer.{Downloader, LibraryHandler, CompileHandler}
  alias MnesiaAssistant.{Transaction, Query, Table}
  alias MnesiaAssistant.Error, as: MError

  @type download_type ::
          :hex
          | :github
          | :github_latest_release
          | :github_latest_tag
          | :github_release
          | :github_tag
          | :url

  @type dep_type :: :none | :force_update

  @type com_type :: :none | :cmd | :port | :mix

  @type branch :: String.t() | {String.t(), [git: boolean()]}

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map() | module() | list(any())}

  @type builder_entry :: {:root, struct() | map(), :edit} | struct() | map()

  @mnesia_info [
    type: :set,
    index: [:app, :type, :dependency_type],
    record_name: __MODULE__,
    storage_properties: [ets: [{:read_concurrency, true}, {:write_concurrency, true}]]
  ]
  ####################################################################################
  ########################## (▰˘◡˘▰) Schema (▰˘◡˘▰) ############################
  ####################################################################################
  guardedstruct do
    @ext_type "hex::github::github_latest_release::github_latest_tag::url::extracted"
    @dep_type "enum=Atom[none::force_update]"
    @compile_type "enum=Atom[cmd::port::mix]"

    field(:id, UUID.t(), auto: {UUID, :generate}, derive: "validate(uuid)")
    field(:app, String.t(), enforce: true, derive: "validate(not_empty_string)")
    field(:version, String.t(), enforce: true, derive: "validate(not_empty_string)")
    field(:type, download_type(), enforce: true, derive: "validate(enum=Atom[#{@ext_type}])")
    field(:path, String.t(), enforce: true, derive: "validate(either=[not_empty_string, url])")
    field(:tag, String.t(), derive: "validate(not_empty_string)")
    field(:release, String.t(), derive: "validate(not_empty_string)")
    field(:branch, branch(), derive: "validate(either=[tuple, not_empty_string])")
    field(:custom_command, String.t(), derive: "validate(not_empty_string)")
    field(:dependency_type, dep_type(), default: :none, derive: "validate(#{@dep_type})")
    field(:compile_type, com_type(), default: :cmd, derive: "validate(#{@compile_type})")
    field(:depends, list(String.t()), default: [], derive: "validate(list)")
    field(:prepend_paths, list(String.t()), default: [], derive: "validate(list)")
    # This type can be used when you want to introduce an event inserted_at unix time(timestamp).
    field(:inserted_at, DateTime.t(), auto: {Extra, :get_unix_time})
    # This type can be used when you want to introduce an event updated_at unix time(timestamp).
    field(:updated_at, DateTime.t(), auto: {Extra, :get_unix_time})
  end

  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  @doc false
  @spec database_config() :: keyword()
  if MishkaInstaller.__information__().env != :test do
    def database_config(),
      do: Keyword.merge(@mnesia_info, attributes: keys(), disc_copies: [node()])
  else
    def database_config(),
      do: Keyword.merge(@mnesia_info, attributes: keys(), ram_copies: [node()])
  end

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @doc """
  This function, in point of fact, combines a number of different methods for downloading,
  compiling, and activating a library within the system. It is possible that this library
  is already present on the system, or it may serve as an update to the version that was
  previously available.

  It ought to be underlined. Adding or updating a library in the system
  is supported by three different techniques in this version of the software.

  1. Obtain the file from `hex.pm` and install it.
  2. Obtain the version from `GitHub` and install it.
  3. Install by utilising the `folder` itself direct.

  > Naturally, it is important to point out that there are also features that can
  > be used to enhance the system's customised functions. In order to accomplish this,
  > the programmer needs to incorporate additional functions into his/her programme,
  > such as downloading from a predetermined URL.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  In reality, the structure of this module `__MODULE__.builder/1`, which likewise possesses
  a high access level validation, is what this function takes as its input.

  It is important to note that this validation and sanitizer is not intended for the user and
  is only necessary for the administrative level of data cleaning. **Pay particular attention
  to the cautions regarding security**.

  **For read more please see this type `MishkaInstaller.Installer.Installer.t()`**.

  ## Example:

  ```elixir
  alias MishkaInstaller.Installer.Installer

  # Normal calling
  Installer.install(%__MODULE__{app: "some_name", path: "some_name", type: :hex})

  # Use builder
  {:ok, hex_tag} = Installer.builder(%{
    app: "mishka_developer_tools",
    version: "0.1.5",
    tag: "0.1.5",
    type: :hex,
    path: "mishka_developer_tools"
  })

  Installer.install(hex_tag)
  ```

  #### More info:

  - `type` --> hex - github - github_latest_release - github_latest_tag - url - extracted
  - `compile_type` --> cmd - port - mix
  - Download methods see `MishkaInstaller.Installer.Downloader`
  """
  @spec install(t()) :: error_return() | okey_return()
  def install(app) when app.type == :extracted do
    with {:ok, data} <- __MODULE__.builder(app),
         :ok <- mix_exist(data.path),
         :ok <- allowed_extract_path(data.path),
         ext_path <- LibraryHandler.extensions_path(),
         :ok <- rename_dir(data.path, "#{ext_path}/#{app.app}-#{app.version}"),
         {:ok, moved_files} <- install_and_compile_steps(data),
         merged_app <- Map.merge(data, %{prepend_paths: moved_files}),
         {:ok, output} <- update_or_write(data, merged_app) do
      MishkaInstaller.broadcast("installer", :install, install_output(output))
      {:ok, install_output(output)}
    end
  after
    File.cd!(MishkaInstaller.__information__().path)
  end

  def install(app) do
    with {:ok, data} <- __MODULE__.builder(app),
         {:ok, archived_file} <- Downloader.download(Map.get(data, :type), data),
         {:ok, path} <- LibraryHandler.move(app, archived_file),
         :ok <- LibraryHandler.extract(:tar, path, "#{app.app}-#{app.version}"),
         {:ok, moved_files} <- install_and_compile_steps(data),
         merged_app <- Map.merge(data, %{prepend_paths: moved_files}),
         {:ok, output} <- update_or_write(data, merged_app) do
      MishkaInstaller.broadcast("installer", :install, install_output(output))
      {:ok, install_output(output, path)}
    end
  after
    File.cd!(MishkaInstaller.__information__().path)
  end

  @doc """
  This function allows you to remove a library's directory from the build folder
  and deactivate the library from runtime.

  > Note that the sub-set libraries are not removed by this function.
  >
  > In later versions, a checker to delete **sub-ap**p libraries might be included.
  > You can add it as a custom for now.


  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ```elixir
  alias MishkaInstaller.Installer.Installer

  # Normal calling
  Installer.uninstall(%__MODULE__{app: "some_name", path: "some_name", type: :hex})
  ```
  """
  @spec uninstall(atom()) :: :ok
  def uninstall(app) do
    Application.stop(app.app)
    Application.unload(app.app)
    info = MishkaInstaller.__information__()
    File.rm_rf!("#{info.path}/_build/#{info.env}/lib/#{app.app}")
    MishkaInstaller.broadcast("installer", :uninstall, app)
    :ok
  end

  @doc """
  The only difference of this function is in the custom path of deleting the build directory.
  See `uninstall/1`.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  """
  @spec uninstall(atom(), Path.t()) :: :ok
  def uninstall(app, custom_path) do
    Application.stop(app)
    Application.unload(app)
    File.rm_rf!(custom_path)
    MishkaInstaller.broadcast("installer", :uninstall, app)
    :ok
  end

  @doc """
  This function is the same as the `install/1` function, with the difference that it executes
  one by one in a simple queue

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  alias MishkaInstaller.Installer.Installer

  # Normal calling
  Installer.async_install(%__MODULE__{app: "some_name", path: "some_name", type: :hex})

  # Use builder
  {:ok, hex_tag} = Installer.builder(%{
    app: "mishka_developer_tools",
    version: "0.1.5",
    tag: "0.1.5",
    type: :hex,
    path: "mishka_developer_tools"
  })

  Installer.async_install(hex_tag)
  ```
  """
  @spec async_install(t()) :: error_return() | :ok
  def async_install(app) do
    case __MODULE__.builder(app) do
      {:ok, data} -> CompileHandler.do_compile(data, :start)
      error -> error
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Query (▰˘◡˘▰) ############################
  ####################################################################################
  @doc """
  To get all runtime libraries information from Mnesia database.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  get()
  ```
  """
  @spec get() :: list(map() | struct())
  def get() do
    pattern = ([__MODULE__] ++ Enum.map(1..length(keys()), fn _x -> :_ end)) |> List.to_tuple()

    Transaction.transaction(fn -> Query.match_object(pattern) end)
    |> case do
      {:atomic, res} ->
        MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        []
    end
  end

  @doc """
  To get a runtime library information from Mnesia database by id.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  get("c63aea42-209a-40fb-b5c6-a0d28ee7e25b")
  ```
  """
  @spec get(String.t()) :: struct() | nil
  def get(id) do
    Transaction.transaction(fn -> Query.read(__MODULE__, id) end)
    |> case do
      {:atomic, res} ->
        MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, []) |> List.first()

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        nil
    end
  end

  @doc """
  To get a runtime library information from Mnesia database by App name.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  get(:app, "mishka_developer_tools")
  ```
  """
  @spec get(:app, String.t()) :: struct() | nil
  def get(field, value) when field in [:app] do
    Transaction.transaction(fn -> Query.index_read(__MODULE__, value, field) end)
    |> case do
      {:atomic, res} ->
        MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])
        |> List.first()

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        nil
    end
  end

  @doc """
  To Add or edit a runtime library information from Mnesia database.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  data = %{app: "uniq", version: "0.6.1", tag: "0.6.1", type: :hex, path: "uniq"}
  write(data)
  ```
  """
  @spec write(builder_entry) :: error_return | okey_return
  def write(data) do
    case builder(data) do
      {:ok, struct} ->
        values_tuple =
          ([__MODULE__] ++ Enum.map(keys(), &Map.get(struct, &1))) |> List.to_tuple()

        Transaction.transaction(fn -> Query.write(values_tuple) end)
        |> case do
          {:atomic, _res} ->
            {:ok, struct}

          {:aborted, reason} ->
            Transaction.transaction_error(reason, __MODULE__, "storing", :global, :database)
        end

      error ->
        error
    end
  end

  @doc """
  To edit a specific field/fields of a runtime library from the Mnesia database.

  > The first input can only be name and ID `[:app]`.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  write(:app, "mishka_developer_tools", %{type: :hex})

  write(:id, "c63aea42-209a-40fb-b5c6-a0d28ee7e25b", %{type: :hex})
  ```
  """
  @spec write(atom(), String.t(), map()) :: error_return | okey_return
  def write(field, value, updated_to) when field in [:app, :id] and is_map(updated_to) do
    selected = if field == :id, do: get(value), else: get(:app, value)

    case selected do
      nil ->
        message =
          "The ID of the record you want to update is incorrect or has already been deleted."

        {:error, [%{message: message, field: :global, action: :write}]}

      data ->
        map =
          Map.merge(data, Map.drop(updated_to, [:id]))
          |> Map.merge(%{updated_at: Extra.get_unix_time()})

        write({:root, map, :edit})
    end
  end

  @doc """
  To get all runtime libraries ids from Mnesia database.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.


  ## Example:

  ```elixir
  ids()
  ```
  """
  @spec ids() :: list(String.t())
  def ids() do
    Transaction.ets(fn -> Table.all_keys(__MODULE__) end)
  end

  @doc """
  To delete a runtime library from Mnesia database by id or name.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  delete(:app, "mishka_developer_tools")

  delete(:id, "c63aea42-209a-40fb-b5c6-a0d28ee7e25b")
  ```
  """
  @spec delete(atom(), String.t()) :: error_return | okey_return
  def delete(field, value) when field in [:id, :app] do
    selected = if field == :id, do: get(value), else: get(:app, value)

    case selected do
      nil ->
        message =
          "The ID of the record you want to delete is incorrect or has already been deleted."

        {:error, [%{message: message, field: :global, action: :delete}]}

      data ->
        Transaction.transaction(fn -> Query.delete(__MODULE__, Map.get(data, :id), :write) end)
        |> case do
          {:atomic, _res} ->
            {:ok, data}

          {:aborted, reason} ->
            Transaction.transaction_error(reason, __MODULE__, "deleting", :global, :database)
        end
    end
  end

  @doc """
  To drop all runtime libraries from Mnesia database.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  drop()
  ```
  """
  @spec drop() :: {:ok, :atomic} | {:error, any(), charlist()}
  def drop() do
    Table.clear_table(__MODULE__)
    |> MError.error_description(__MODULE__)
  end

  @doc """
  To check is a runtime library unique or not in Mnesia database.

  > It returns `:ok`, or `{:error, reason}`. Note that if the requested runtime library does not exist,
  > It means it is unique, and if it is already in the database, it means it is not unique

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  unique(:app, "mishka_developer_tools")
  ```
  """
  @spec unique(:app, String.t()) :: :ok | error_return()
  def unique(field, value) do
    case get(field, value) do
      nil ->
        :ok

      _data ->
        message = "This event already exists in the database."
        {:error, [%{message: message, field: :global, action: :unique}]}
    end
  end

  @doc """
  This function is exactly like `unique/2` function, except that its output is a Boolean.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  unique?(:app, "mishka_developer_tools")
  ```
  """
  @spec unique?(:app, String.t()) :: boolean()
  def unique?(field, value), do: is_nil(get(field, value))
  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  defp mix_exist(path) do
    with true <- File.dir?(path),
         files_list <- File.ls!(path),
         true <- "mix.exs" in files_list do
      :ok
    else
      _ ->
        message =
          "There is no mix.exs file in the specified path (directory). Please use Elixir standard library."

        {:error, [%{message: message, field: :global, action: :mix_exist}]}
    end
  end

  defp rename_dir(path, name_path) do
    case File.rename(path, name_path) do
      :ok ->
        File.rm_rf!(path)
        :ok

      {:error, source} ->
        File.rm_rf!(path)
        message = "There was a problem moving the file."
        {:error, [%{message: message, field: :path, action: :rename_dir, source: source}]}
    end
  end

  defp allowed_extract_path(extract_path) do
    if String.starts_with?(extract_path, LibraryHandler.extensions_path()) do
      :ok
    else
      message = "Your library extraction path is not correct."
      allowed = LibraryHandler.extensions_path()
      {:error, [%{message: message, field: :path, action: :rename_dir, allowed: allowed}]}
    end
  end

  defp install_and_compile_steps(data) do
    with :ok <- LibraryHandler.do_compile(data),
         {:ok, moved_files} <- LibraryHandler.move_and_replace_build_files(data),
         :ok <- LibraryHandler.prepend_compiled_apps(moved_files),
         :ok <- LibraryHandler.unload(String.to_atom(data.app)),
         :ok <- LibraryHandler.application_ensure(String.to_atom(data.app)) do
      {:ok, moved_files}
    end
  end

  defp update_or_write(data, merged_app) do
    db_data = get(data.app)
    if is_nil(db_data), do: write(merged_app), else: write(:id, db_data.id, merged_app)
  end

  defp install_output(data, download \\ nil) do
    ext_path = LibraryHandler.extensions_path()
    %{download: download, extension: data, dir: "#{ext_path}/#{data.app}-#{data.version}"}
  end
end
