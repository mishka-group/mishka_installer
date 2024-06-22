defmodule MishkaInstaller.Installer.Installer do
  use GuardedStruct
  alias MishkaDeveloperTools.Helper.{Extra, UUID}
  alias MishkaInstaller.Installer.{Downloader, LibraryHandler}

  @type download_type ::
          :hex
          | :github
          | :github_latest_release
          | :github_latest_tag
          | :github_release
          | :github_tag
          | :url

  @type dep_type :: :none | :force_update

  @type branch :: String.t() | {String.t(), [git: boolean()]}

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
    @ext_type "hex::github::github_latest_release::github_latest_tag::url"
    @dep_type "enum=Atom[none::force_update]"

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
    field(:depends, list(String.t()), default: [], derive: "validate(list)")
    field(:checksum, String.t(), derive: "validate(not_empty_string)")
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
  def install(app) do
    with {:ok, data} <- __MODULE__.builder(app),
         {:ok, archived_file} <- Downloader.download(Map.get(data, :type), data),
         {:ok, path} <- LibraryHandler.move(app, archived_file),
         :ok <- LibraryHandler.extract(:tar, path) do
      {:ok,
       %{
         download: path,
         extensions: data,
         dir: "#{LibraryHandler.extensions_path()}/#{app.app}-#{app.version}"
       }}
    end

    # TODO: Create an item inside LibraryHandler queue
    # |__ TODO: CheckSum file if exist
    # |__ TODO: Do compile based on strategy developer wants
    # |__ TODO: Store builded files for re-start project
    # |__ TODO: Do runtime steps
    # |__ TODO: Update all stuff in mnesia db
    # |__ TODO: Re-cover if the process not correct, especially mix manipulating
  after
    File.cd!("/Users/shahryar/Documents/Programming/Elixir/mishka_installer")
  end

  def uninstall(%__MODULE__{} = _app) do
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Query (▰˘◡˘▰) ############################
  ####################################################################################

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
end
