defmodule MishkaInstaller.Event.Event do
  use GuardedStruct
  alias MishkaDeveloperTools.Helper.{Extra, UUID}
  import MnesiaAssistant, only: [er: 1, erl_fields: 4]
  alias MnesiaAssistant.{Transaction, Query, Table}
  alias MnesiaAssistant.Error, as: MError
  alias MishkaInstaller.Event.EventHandler

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

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec register(module(), String.t(), map()) :: error_return | okey_return
  def register(name, event, initial) do
    with {:ok, _module} <- ensure_loaded(name),
         merged <- Map.merge(initial, %{name: name, extension: name.config(:app), event: event}),
         {:ok, struct} <- builder(merged),
         deps_list <- allowed_events(struct.depends),
         {:ok, db_plg} <-
           write(Map.merge(struct, depends_status(deps_list, struct.status))),
         :ok <- MishkaInstaller.broadcast("event", :register, db_plg) do
      {:ok, db_plg}
    end
  end

  @spec start(:name | :event, module() | String.t()) :: error_return | okey_return
  def start(:name, name) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         :ok <- plugin_status(data.status),
         :ok <- allowed_events?(data.depends),
         {:ok, db_plg} <- write(:id, data.id, %{status: :started}),
         _ok <- EventHandler.do_compile(db_plg.event, :start) do
      {:ok, db_plg}
    end
  end

  def start(:event, event) do
    case get(:event, event) do
      [] ->
        message =
          "There are no plugins in the database that can be started for this event."

        {:error, [%{message: message, field: :global, action: :start_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            with :ok <- plugin_status(pl_item.status),
                 :ok <- allowed_events?(pl_item.depends),
                 {:ok, db_plg} <- write(:id, pl_item.id, %{status: :started}) do
              acc ++ [db_plg]
            else
              _ -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :start)
        {:ok, sorted_plugins}
    end
  end

  @spec start() :: okey_return() | error_return()
  def start() do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &start(:event, &1))
          |> Enum.reject(&(is_tuple(&1) and elem(&1, 0) == :error))

        {:ok, sorted_events}

      error ->
        error
    end
  end

  @spec restart(:name | :event, module() | String.t()) :: error_return | okey_return
  def restart(:name, name) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         deps_list <- allowed_events(data.depends),
         {:ok, db_plg} <- write(:id, data.id, depends_status(deps_list, :restarted)),
         :ok <- plugin_status(db_plg.status),
         _ok <- EventHandler.do_compile(db_plg.event, :restart) do
      {:ok, db_plg}
    end
  end

  def restart(:event, event) do
    case get(:event, event) do
      [] ->
        message =
          "There are no plugins in the database that can be started for this event."

        {:error, [%{message: message, field: :global, action: :restart_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            with {:ok, data} <- exist_record?(get(:name, pl_item.name)),
                 deps_list <- allowed_events(data.depends),
                 {:ok, db_plg} <- write(:id, data.id, depends_status(deps_list, :restarted)),
                 :ok <- plugin_status(db_plg.status) do
              acc ++ [db_plg]
            else
              _ -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :restart)
        {:ok, sorted_plugins}
    end
  end

  @spec restart() :: okey_return() | error_return()
  def restart() do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &restart(:event, &1))
          |> Enum.reject(&(is_tuple(&1) and elem(&1, 0) == :error))

        {:ok, sorted_events}

      error ->
        error
    end
  end

  @spec stop(:name | :event, module() | String.t()) :: okey_return() | error_return()
  def stop(:name, name) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         :ok <- plugin_status(data.status),
         {:ok, db_plg} <- write(:id, data.id, %{status: :stopped}),
         _ok <- EventHandler.do_compile(db_plg.event, :stop) do
      {:ok, db_plg}
    end
  end

  def stop(:event, event) do
    case get(:event, event) do
      [] ->
        message =
          "There are no plugins in the database that can be started for this event."

        {:error, [%{message: message, field: :global, action: :restart_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            with {:ok, data} <- exist_record?(get(:name, pl_item.name)),
                 :ok <- plugin_status(data.status),
                 {:ok, db_plg} <- write(:id, data.id, %{status: :stopped}) do
              acc ++ [db_plg]
            else
              _ -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :stop)
        {:ok, sorted_plugins}
    end
  end

  @spec stop() :: okey_return() | error_return()
  def stop() do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &stop(:event, &1))
          |> Enum.reject(&(is_tuple(&1) and elem(&1, 0) == :error))

        {:ok, sorted_events}

      error ->
        error
    end
  end

  @spec unregister(:name | :event, module() | String.t()) :: okey_return() | error_return()
  def unregister(:name, name) do
    with {:ok, db_plg} <- delete(:name, name),
         :ok <- GenServer.stop(name, :normal),
         _ok <- EventHandler.do_compile(db_plg.event, :unregister) do
      {:ok, db_plg}
    end
  end

  def unregister(:event, event) do
    case get(:event, event) do
      [] ->
        message =
          "There are no plugins in the database that can be started for this event."

        {:error, [%{message: message, field: :global, action: :restart_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            with {:ok, db_plg} <- delete(:name, pl_item.name),
                 :ok <- GenServer.stop(pl_item.name, :normal) do
              acc ++ [db_plg]
            else
              _ -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :unregister)
        {:ok, sorted_plugins}
    end
  end

  @spec unregister() :: okey_return() | error_return()
  def unregister() do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &unregister(:event, &1))
          |> Enum.reject(&(is_tuple(&1) and elem(&1, 0) == :error))

        {:ok, sorted_events}

      error ->
        error
    end
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

        {:error, [%{message: message, field: :global, action: :write}]}

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

  def unique(field, value) do
    case get(field, value) do
      nil ->
        :ok

      _data ->
        message = "This event already exists in the database."
        {:error, [%{message: message, field: :global, action: :unique}]}
    end
  end

  def unique?(field, value), do: is_nil(get(field, value))
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

  @spec allowed_events(list()) :: list()
  def allowed_events(deps_list) do
    Enum.reduce(deps_list, [], fn item, acc ->
      with struct when not is_nil(struct) <- get(:name, item),
           true <- struct.status not in [:registered, :stopped, :held] do
        acc
      else
        _ -> acc ++ [item]
      end
    end)
  end

  @spec allowed_events?(list(any())) :: :ok | error_return()
  def allowed_events?(deps_list) do
    if allowed_events(deps_list) != [] do
      message = "This plugin has dependencies that are not yet activated in the system"
      {:error, [%{message: message, field: :global, action: :hold_statuses}]}
    else
      :ok
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @doc false

  defp depends_status([], status), do: %{status: status}

  defp depends_status(_deps, _status), do: %{status: :held}

  @doc false
  @spec plugin_status(:stopped | :held) :: :ok | error_return()
  def plugin_status(status) when status in [:stopped, :held] do
    message = "The status of the plugin is not allowed."
    {:error, [%{message: message, field: :global, action: :plugin_status}]}
  end

  def plugin_status(_status), do: :ok

  defp exist_record?(nil) do
    message =
      "The ID of the record you want is incorrect or has already been deleted."

    {:error, [%{message: message, field: :global, action: :exist_record?}]}
  end

  defp exist_record?(data), do: {:ok, data}
end
