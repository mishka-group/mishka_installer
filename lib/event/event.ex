defmodule MishkaInstaller.Event.Event do
  use GuardedStruct
  alias MishkaDeveloperTools.Helper.{Extra, UUID}
  import MnesiaAssistant, only: [er: 1, erl_fields: 4]
  alias MnesiaAssistant.{Transaction, Query, Table}
  alias MnesiaAssistant.Error, as: MError

  @mnesia_info [
    type: :set,
    index: [:name, :event, :extension],
    record_name: __MODULE__,
    storage_properties: [ets: [{:read_concurrency, true}, {:write_concurrency, true}]]
  ]
  ####################################################################################
  ########################## (▰˘◡˘▰) Schema (▰˘◡˘▰) ############################
  ####################################################################################
  @type status() :: :registered | :started | :stopped | :restarted | :held

  guardedstruct do
    # This type can be used when you want to introduce an plugin id.
    field(:id, UUID.t(), auto: {UUID, :generate}, derive: "validate(uuid)")
    # This type can be used when you want to introduce an plugin name.
    field(:name, module(), enforce: true, derive: "validate(atom)")
    # This type can be used when you want to introduce an event name.
    field(:event, String.t(), enforce: true, derive: "validate(not_empty_string)")
    # This type can be used when you want to introduce a priority of calling an event.
    field(:priority, integer(), default: 100, derive: "validate(integer, min_len=0, max_len=100)")
    # This type can be used when you want to introduce a status for an event.
    field(:status, status(),
      derive: "validate(enum=Atom[registered::started::stopped::restarted::held])",
      default: :registered
    )

    # This type can be used when you want to introduce an event owner extension.
    field(:extension, atom(), enforce: true, derive: "validate(atom)")

    # This type can be used when you want to introduce a list of modules that an event depend on them.
    field(:depends, list(String.t()), default: [], derive: "validate(list)")
    # This type can be used when you want to introduce an extra data for an event.
    field(:extra, list(map()), default: [], derive: "validate(list)")
    # This type can be used when you want to introduce an event inserted_at unix time(timestamp).
    field(:inserted_at, DateTime.t(), auto: {Extra, :get_unix_time})
    # This type can be used when you want to introduce an event updated_at unix time(timestamp).
    field(:updated_at, DateTime.t(), auto: {Extra, :get_unix_time})
  end

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}
  @type okey_return :: {:ok, struct() | map() | module() | list(any())}
  @type builder_entry :: {:root, struct() | map(), :edit} | struct() | map()
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

  ###################################################################################
  ############################ (▰˘◡˘▰) Query (▰˘◡˘▰) ##########################
  ###################################################################################
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

  @spec get(:name | :event | :extension, module() | String.t()) ::
          list(map() | struct()) | map() | struct() | nil
  def get(field, value) when field in [:name, :event, :extension] do
    Transaction.transaction(fn -> Query.index_read(__MODULE__, value, field) end)
    |> case do
      {:atomic, res} ->
        data = MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])
        if field in [:event, :extension], do: data, else: List.first(data)

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        if field in [:event, :extension], do: [], else: nil
    end
  end

  @spec get(String.t()) :: map() | struct() | nil
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

  @spec write(atom(), String.t() | module(), map()) :: error_return | okey_return
  def write(field, value, updated_to) when field in [:id, :name] and is_map(updated_to) do
    selected = if field == :id, do: get(value), else: get(:name, value)

    case selected do
      nil ->
        message =
          "The ID of the record you want to update is incorrect or has already been deleted."

        {:error, [%{message: message, field: :global, action: :not_exist}]}

      data ->
        map =
          Map.merge(data, updated_to)
          |> Map.merge(%{updated_at: Extra.get_unix_time()})

        write({:root, map, :edit})
    end
  end

  @spec ides() :: list(String.t())
  def ides() do
    Transaction.ets(fn -> Table.all_keys(__MODULE__) end)
  end

  @spec group_events(list(atom())) :: error_return() | okey_return()
  def group_events(key \\ [:event]) do
    Transaction.transaction(fn ->
      Query.select(__MODULE__, [{erl_fields({__MODULE__}, keys(), key, 1), [], er(:selected)}])
    end)
    |> case do
      {:atomic, result} ->
        {:ok, List.flatten(result) |> Enum.uniq()}

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "deleting", :global, :database)
    end
  end

  @spec delete(atom(), String.t() | module()) :: error_return | okey_return
  def delete(field, value) when field in [:id, :name] do
    selected = if field == :id, do: get(value), else: get(:name, value)

    case selected do
      nil ->
        message =
          "The ID of the record you want to delete is incorrect or has already been deleted."

        {:error, [%{message: message, field: :global, action: :not_exist}]}

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

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  # Just should be used when you need one time or in compile time
  @spec ensure_loaded(module()) :: error_return | okey_return
  def ensure_loaded(module) do
    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      message = "This module is not loaded in the system."
      {:error, [%{message: message, field: :global, action: :ensure_loaded}]}
    end
  end
end
