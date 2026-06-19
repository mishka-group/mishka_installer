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

  ## Pre-built `ebin` only (works in a release)

  This module installs a **pre-built** library, i.e. its already compiled `ebin` (the
  `ebin/*.beam` files and the `ebin/<app>.app` resource). It does **not** compile at runtime.

  Runtime compilation (`mix deps.get`/`deps.compile`/`compile`) is intentionally **not** supported,
  because a production `release` ships no `Mix`, no `Hex`, no project source and no `_build` tree, so
  there is nothing to compile with. Instead the artifacts are placed in a writable extensions
  directory, added to the code path and loaded:

  - `Code.prepend_path/1` then `Application.load/1` + `Application.ensure_all_started/1`.

  Build the artifacts on a machine that uses the **same** Erlang/OTP and Elixir as the host.

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

  #### Note:
  > If you are using Phoenix as developer mode, please disable `live_reload` in `dev.exs`.
  > Please add `reloadable_apps: [:mishka_installer]` to your endpoint config in `config.exs` file.
  """
  use GuardedStruct
  require Logger
  alias MishkaInstaller.Helper.{Extra, UUID}
  alias MishkaInstaller.Installer.{Downloader, LibraryHandler, CompileHandler}
  alias MishkaInstaller.MnesiaAssistant.{Transaction, Query, Table}
  alias MishkaInstaller.MnesiaAssistant.Error, as: MError

  @type download_type :: :path | :url | :github_tag | :github_latest_release

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map() | module() | list(any())}

  @type builder_entry :: {:root, struct() | map(), :edit} | struct() | map()

  @name_pattern ~r/^[a-z][a-z0-9_]*$/

  @mnesia_info [
    type: :set,
    index: [:app],
    record_name: __MODULE__,
    storage_properties: [ets: [{:read_concurrency, true}, {:write_concurrency, true}]]
  ]
  ####################################################################################
  ########################## (▰˘◡˘▰) Schema (▰˘◡˘▰) ############################
  ####################################################################################
  guardedstruct do
    # This type can be used when you want to introduce a runtime library id.
    field(:id, UUID.t(), auto: {UUID, :generate}, derives: "validate(uuid)")
    # This type can be used when you want to introduce a runtime library (OTP app) name.
    field(:app, String.t(), enforce: true, derives: "validate(not_empty_string)")
    # This type can be used when you want to introduce a runtime library version.
    field(:version, String.t(), enforce: true, derives: "validate(not_empty_string)")
    # `:path` (a local package dir) or download a `tar.gz` artifact (`:url`/`:github_*`).
    field(:type, download_type(),
      default: :path,
      derives: "validate(enum=Atom[path::url::github_tag::github_latest_release])"
    )

    # `:path` = local package dir; `:url` = artifact URL; `:github_*` = "owner/repo".
    field(:path, String.t(), enforce: true, derives: "validate(not_empty_string)")
    # The release tag for `:github_tag` downloads.
    field(:tag, String.t(), derives: "validate(not_empty_string)")

    # The optional release asset name to pick for `:github_*` downloads (defaults to the first asset).
    field(:asset, String.t(), derives: "validate(not_empty_string)")
    # Optional sha256 (hex) of the downloaded artifact; verified before extraction when present.
    field(:checksum, String.t(), derives: "validate(not_empty_string)")

    # This type can be used when you want to introduce a list of apps that a library depend on them.
    field(:depends, list(String.t()), default: [], derives: "validate(list)")
    # The `{app, ebin_path}` list added to the code path; replayed on every boot to re-activate.
    field(:prepend_paths, list(String.t()), default: [], derives: "validate(list)")
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
  This function activates a **pre-built** library (its compiled `ebin`) within the running system.
  It is possible that this library is already present on the system, or it may serve as an update
  to the version that was previously available.

  The package is a `ebin` directory plus a `ebin/<app>.app` resource. The `type` decides how it is
  obtained: `:path` uses a local package already inside the extensions directory (see
  `MishkaInstaller.Installer.LibraryHandler.extensions_path/0`); `:url`/`:github_tag`/
  `:github_latest_release` **download** a pre-built `tar.gz` artifact and extract it there. Nothing
  is ever compiled here (see `MishkaInstaller.Installer.Downloader`).

  The steps are: validate the app name, resolve the package (local move or download + extract),
  confirm the `ebin`/`.app` exist, reject a same/older version that is already running, add the
  `ebin` to the code path (`Code.prepend_path/1`), then `Application.load/1` +
  `Application.ensure_all_started/1`. On any failure **after** the code path is touched, the partial
  install is rolled back so the node is left clean.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > Loading a `.beam` is **running arbitrary code with full node privileges**; the BEAM has no
  > sandbox. Only install artifacts from a trusted source, built for the **same** Erlang/OTP and
  > Elixir as the host.

  In reality, the structure of this module `__MODULE__.builder/1`, which likewise possesses
  a high access level validation, is what this function takes as its input.

  **For read more please see this type `MishkaInstaller.Installer.Installer.t()`**.

  ## Example:

  ```elixir
  alias MishkaInstaller.Installer.Installer

  # `path` points to the pre-built package placed inside the extensions directory.
  {:ok, lib} = Installer.builder(%{
    app: "mishka_developer_tools",
    version: "0.1.5",
    path: "<extensions_path>/mishka_developer_tools-0.1.5"
  })

  Installer.install(lib)
  ```
  """
  @spec install(t()) :: error_return() | okey_return()
  def install(app) do
    with {:ok, data} <- __MODULE__.builder(app),
         :ok <- valid_name(data.app),
         {:ok, dest} <- fetch_package(data),
         :ok <- ebin_exist(dest),
         _ <- warn_on_native(dest, data.app),
         {:ok, _props} <-
           LibraryHandler.read_app(safe_atom(data.app), app_resource(dest, data.app)),
         :ok <-
           LibraryHandler.compare_version_with_installed_app(safe_atom(data.app), data.version),
         {:ok, prepend_paths} <- install_steps(data, dest),
         merged_app <- Map.merge(data, %{prepend_paths: prepend_paths}),
         {:ok, output} <- update_or_write(data, merged_app) do
      MishkaInstaller.broadcast("installer", :install, install_output(output))
      {:ok, install_output(output)}
    end
  after
    File.cd!(MishkaInstaller.__information__().path)
  end

  @doc """
  This function deactivates a library from runtime and removes its pre-built package from the
  extensions directory.

  It stops and unloads the application, drops its `ebin` from the code path, deletes the
  `"<app>-<version>"` directory and removes the record from the database.

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
  Installer.uninstall(%__MODULE__{app: "some_name", version: "0.1.0", path: "some_path"})
  ```
  """
  @spec uninstall(t() | map()) :: :ok
  def uninstall(app) do
    app_atom = safe_atom(app.app)
    ext_path = LibraryHandler.extensions_path()
    Application.stop(app_atom)
    Application.unload(app_atom)
    Code.delete_path("#{ext_path}/#{app.app}-#{app.version}/ebin")
    File.rm_rf!("#{ext_path}/#{app.app}-#{app.version}")
    delete(:app, app.app)
    MishkaInstaller.broadcast("installer", :uninstall, app)
    :ok
  end

  @doc """
  This function is the same as the `install/1` function, with the difference that it executes
  one by one in a simple queue (`MishkaInstaller.Installer.CompileHandler`).

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  alias MishkaInstaller.Installer.Installer

  {:ok, lib} = Installer.builder(%{
    app: "mishka_developer_tools",
    version: "0.1.5",
    path: "<extensions_path>/mishka_developer_tools-0.1.5"
  })

  Installer.async_install(lib)
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
        MishkaInstaller.MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])

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
        MishkaInstaller.MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, []) |> List.first()

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
        MishkaInstaller.MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])
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
  defp fetch_package(%{type: :path} = data) do
    dest = "#{LibraryHandler.extensions_path()}/#{data.app}-#{data.version}"

    with :ok <- allowed_extract_path(data.path),
         :ok <- place_package(data.path, dest) do
      {:ok, dest}
    end
  end

  defp fetch_package(data) do
    name = "#{data.app}-#{data.version}"

    with {:ok, body} <- Downloader.download(data.type, download_pkg(data)),
         :ok <- verify_checksum(body, Map.get(data, :checksum)),
         :ok <- LibraryHandler.extract(:tar, body, name) do
      {:ok, "#{LibraryHandler.extensions_path()}/#{name}"}
    end
  end

  defp download_pkg(data) do
    %{path: data.path}
    |> maybe_put(:tag, Map.get(data, :tag))
    |> maybe_put(:asset, Map.get(data, :asset))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp verify_checksum(_body, nil), do: :ok

  defp verify_checksum(body, expected) do
    actual = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)

    if actual == String.downcase(expected) do
      :ok
    else
      message = "The downloaded artifact does not match the expected sha256 checksum."
      {:error, [%{message: message, field: :checksum, action: :verify_checksum}]}
    end
  end

  defp warn_on_native(dest, app) do
    natives = Path.wildcard("#{dest}/priv/**/*.{so,dll,dylib}")

    if natives != [] do
      Logger.warning(
        "[mishka_installer.installer] #{app} ships native artifacts (#{inspect(natives)}); they must match this host's OS/arch/ERTS."
      )
    end

    :ok
  end

  defp valid_name(app) do
    if Regex.match?(@name_pattern, "#{app}") and String.length("#{app}") <= 255 do
      :ok
    else
      message =
        "The application name is invalid. Use only lowercase letters, digits and underscores."

      {:error, [%{message: message, field: :app, action: :valid_name}]}
    end
  end

  defp safe_atom(app), do: String.to_atom(app)

  defp app_resource(path, app), do: "#{path}/ebin/#{app}.app"

  defp ebin_exist(path) do
    with true <- File.dir?("#{path}/ebin"),
         files_list <- File.ls!("#{path}/ebin"),
         true <- Enum.any?(files_list, &String.ends_with?(&1, ".app")) do
      :ok
    else
      _ ->
        message =
          "There is no compiled `ebin` directory (with a `.app` file) in the specified path. " <>
            "Please provide the pre-built artifacts of the library."

        {:error, [%{message: message, field: :path, action: :ebin_exist}]}
    end
  end

  defp allowed_extract_path(extract_path) do
    allowed = LibraryHandler.extensions_path()

    if String.starts_with?(Path.expand(extract_path), Path.expand(allowed)) do
      :ok
    else
      message = "Your library path is not allowed. It must be inside the extensions directory."

      {:error,
       [%{message: message, field: :path, action: :allowed_extract_path, allowed: allowed}]}
    end
  end

  defp place_package(source, dest) do
    if Path.expand(source) == Path.expand(dest), do: :ok, else: rename_dir(source, dest)
  end

  defp rename_dir(path, name_path) do
    File.rm_rf!(name_path)

    case File.rename(path, name_path) do
      :ok ->
        :ok

      {:error, source} ->
        message = "There was a problem moving the file."
        {:error, [%{message: message, field: :path, action: :rename_dir, source: source}]}
    end
  end

  defp install_steps(data, dest) do
    app = safe_atom(data.app)
    ebin = "#{dest}/ebin"
    prepend_paths = [{app, ebin}]

    with :ok <- LibraryHandler.prepend_compiled_apps(prepend_paths),
         _ <- Application.stop(app),
         :ok <- LibraryHandler.unload(app),
         :ok <- LibraryHandler.application_ensure(app) do
      {:ok, prepend_paths}
    else
      error ->
        Application.stop(app)
        Application.unload(app)
        Code.delete_path(ebin)
        error
    end
  end

  defp update_or_write(data, merged_app) do
    db_data = get(data.app)
    if is_nil(db_data), do: write(merged_app), else: write(:id, db_data.id, merged_app)
  end

  defp install_output(data) do
    ext_path = LibraryHandler.extensions_path()
    %{extension: data, dir: "#{ext_path}/#{data.app}-#{data.version}"}
  end
end
