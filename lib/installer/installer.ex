defmodule MishkaInstaller.Installer.Installer do
  use GuardedStruct
  alias MishkaDeveloperTools.Helper.{Extra, UUID}
  alias MishkaInstaller.Installer.{Downloader, LibraryHandler}
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
    @compile_type "enum=Atom[none::cmd::port::mix]"

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
  if Mix.env() != :test do
    def database_config(),
      do: Keyword.merge(@mnesia_info, attributes: keys(), disc_copies: [node()])
  else
    def database_config(),
      do: Keyword.merge(@mnesia_info, attributes: keys(), ram_copies: [node()])
  end

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  def install(app) when app.type == :extracted do
    with {:ok, data} <- __MODULE__.builder(app),
         :ok <- unique(:app, data.app),
         :ok <- mix_exist(data.path),
         :ok <- allowed_extract_path(data.path),
         ext_path <- LibraryHandler.extensions_path(),
         :ok <- rename_dir(data.path, "#{ext_path}/#{app.app}-#{app.version}") do
      {:ok, %{download: nil, extensions: data, dir: "#{ext_path}/#{app.app}-#{app.version}"}}
    end
  after
    File.cd!(MishkaInstaller.__information__().path)
  end

  def install(app) do
    with {:ok, data} <- __MODULE__.builder(app),
         :ok <- unique(:app, data.app),
         {:ok, archived_file} <- Downloader.download(Map.get(data, :type), data),
         {:ok, path} <- LibraryHandler.move(app, archived_file),
         :ok <- LibraryHandler.extract(:tar, path, "#{app.app}-#{app.version}"),
         ext_path <- LibraryHandler.extensions_path() do
      {:ok, %{download: path, extensions: data, dir: "#{ext_path}/#{app.app}-#{app.version}"}}
    end

    # TODO: Create an item inside LibraryHandler queue
    # |__ TODO: Do compile based on strategy developer wants
    # |__ TODO: Store builded files for re-start project
    # |__ TODO: Do runtime steps
    # |__ TODO: Update all stuff in mnesia db
  after
    File.cd!(MishkaInstaller.__information__().path)
  end

  def update() do
  end

  def uninstall(%__MODULE__{} = _app) do
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Query (▰˘◡˘▰) ############################
  ####################################################################################
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
          Map.merge(data, updated_to)
          |> Map.merge(%{updated_at: Extra.get_unix_time()})

        write({:root, map, :edit})
    end
  end

  @spec ids() :: list(String.t())
  def ids() do
    Transaction.ets(fn -> Table.all_keys(__MODULE__) end)
  end

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

  @spec drop() :: {:ok, :atomic} | {:error, any(), charlist()}
  def drop() do
    Table.clear_table(__MODULE__)
    |> MError.error_description(__MODULE__)
  end

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
end
