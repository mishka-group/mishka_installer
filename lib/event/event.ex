defmodule MishkaInstaller.Event.Event do
  @moduledoc """
  The `MishkaInstaller.Event.Event` module is the core of events, which comprises pre-prepared
  strategies for the implementation and management of plugins introduced to the system
  around various events.
  These implementation and management strategies are included in the Event module.

  > #### Use cases information {: .tip}
  >
  > The fundamental criteria of the same system serve as the basis for the specification of
  > these strategies, which are aimed at common systems.
  > Therefore, you are not permitted to utilize this module if you believe that
  > your technique is different.

  In addition, it is important to remember that the other part of this module is
  connected to the queries that are required to be made to the **Erlang runtime database**,
  which is known as `Mnesia`.

  Using this functionality, you will be able to store the information that is
  associated with each plugin in it.

  > Note that all storages are based on the name of an event. See `MishkaInstaller.Event.Hook` module.

  ---

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.

  ### Note:

  When you are writing, you should always make an effort to be more careful because
  you might get reconditioned during times of high traffic.
  When it comes to reading and running all plugins, this problem only occurs when a
  module is being created and destroyed during the compilation process.
  """
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
  @doc """
  If you want to store a plugin for a particular event, this function is a predefined strategy
  that you can use. Additionally, it performs a check on the integrity of the plugin module and
  gathers other information that is necessary while it is being stored in `Mnesia`.

  Inputs for this function include the **name of the plugin**, **the name of the event**, and some
  **fundamental information**.
  Checking the `struct` of this module is one way to add the `initial event` to the modules.

  See: `%MishkaInstaller.Event.Event{}`

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.
  >
  > It is not appropriate for the user to have any direct influence on this function because
  > it is intended for the use of the programmer. It should be brought to your attention that
  > this particular function, which incorporates the `Write` activity, should often be utilized
  > only once at the beginning of the project.

  ## Example:

  ```elixir
  register(TestApp.User.Auth, "after_login", %{priority: 2})
  ```

  > This function is only responsible for registering the plugin; it does not carry
  > out any activities related to execution. Please refer to function `start/2` in order to execute
  """
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

  @doc """
  A pre-made strategy for starting a plugin is what this method is clearly named.
  Keep in mind that you'll need to register this plugin ahead of time.

  The requested Event will be compiled once more in the event that the
  plugin is able to start properly. **This is a heavy write activity**

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.
  >
  > It is not appropriate for the user to have any direct influence on this function because
  > it is intended for the use of the programmer. It should be brought to your attention that
  > this particular function, which incorporates the `Write` activity, should often be utilized
  > only once at the beginning of the project.

  ##### Compile path: `MishkaInstaller.Event.ModuleStateCompiler.State.YourEvent`.

  ## Example:

  ```elixir
  # Start a plugin
  start(:name, TestApp.User.Auth)

  # Start all plugins of an event
  start(:event, "after_login")
  ```
  """
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

  @doc """
  This function starts all events, For more information please see `start/2`.
  """
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

  @doc """
  A pre-made strategy for restarting a plugin is what this method is clearly named.
  Keep in mind that you'll need to register and start this plugin ahead of time.

  The requested Event will be compiled once more in the event that the
  plugin is able to restart properly. **This is a heavy write activity**


  > #### Use cases information {: .tip}
  >
  > The `start/2` function and this idea are often mistaken. Actually, this function does
  > the same operations as the start function, but it re-examines the conditions.
  > You can tailor your own function to meet the specific needs of your system, and there's
  > already a plan in place. The `MishkaInstaller.Event.Hook` module decides on this potential.


  ---


  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.
  >
  > It is not appropriate for the user to have any direct influence on this function because
  > it is intended for the use of the programmer. It should be brought to your attention that
  > this particular function, which incorporates the `Write` activity, should often be utilized
  > only once at the beginning of the project.

  ##### Compile path: `MishkaInstaller.Event.ModuleStateCompiler.State.YourEvent`.

  ## Example:

  ```elixir
  # Restart a plugin
  restart(:name, TestApp.User.Auth)

  # Restart all plugins of an event
  restart(:event, "after_login")
  ```
  """
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

  @doc """
  This function restarts all events, For more information please see `restart/2`.
  """
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

  @doc """
  A pre-made strategy for stopping a plugin is what this method is clearly named.
  Keep in mind that you'll need to register and start this plugin ahead of time.

  The requested Event will be compiled once more in the event that the
  plugin is able to stop properly. **This is a heavy write activity**

  > #### Use cases information {: .tip}
  >
  > Keep in mind that the only thing that happens when you stop a plugin is that its database status
  > changes to `stopped` and it is removed from the list of compiled modules
  > of the event in question. However, its modules, notably `GenServer`,
  > will still be operational and will not be entirely removed from the system.

  ---

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.
  >
  > It is not appropriate for the user to have any direct influence on this function because
  > it is intended for the use of the programmer. It should be brought to your attention that
  > this particular function, which incorporates the `Write` activity, should often be utilized
  > only once at the beginning of the project.

  ## Example:

  ```elixir
  # Stop a plugin
  stop(:name, TestApp.User.Auth)

  # Stop all plugins of an event
  stop(:event, "after_login")
  ```
  """
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

  @doc """
  This function stops all events, For more information please see `stop/2`.
  """
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

  @doc """
  This function removes the plugin from the database and **kills** all processes associated to it,
  in addition to doing the exact same thing as the `stop/2` function.


  The requested Event will be compiled once more in the event that the
  plugin is able to unregister properly. **This is a heavy write activity**

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > This module is a read-only in-memory storage optimized for the fastest possible read times
  > not for write strategies.
  >
  > It is not appropriate for the user to have any direct influence on this function because
  > it is intended for the use of the programmer. It should be brought to your attention that
  > this particular function, which incorporates the `Write` activity, should often be utilized
  > only once at the beginning of the project.

  ## Example:

  ```elixir
  # Unregister a plugin
  unregister(:name, TestApp.User.Auth)

  # Unregister all plugins of an event
  unregister(:event, "after_login")
  ```
  """
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

  @doc """
  This function stops all unregisters, For more information please see `unregister/2`.
  """
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
  @doc """

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

  """
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

  @doc """

  """
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

  @doc """

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

  """
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

  @doc """

  """
  @spec ides() :: list(String.t())
  def ides() do
    Transaction.ets(fn -> Table.all_keys(__MODULE__) end)
  end

  @doc """

  """
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

  @doc """

  """
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

  @doc """

  """
  @spec drop() :: {:ok, :atomic} | {:error, any(), charlist()}
  def drop() do
    Table.clear_table(__MODULE__)
    |> MError.error_description(__MODULE__)
  end

  @doc """

  """
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

  """
  def unique?(field, value), do: is_nil(get(field, value))
  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  # Just should be used when you need one time or in compile time
  @doc false
  @spec ensure_loaded(module()) :: error_return | okey_return
  def ensure_loaded(module) do
    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      message = "This module is not loaded in the system."
      {:error, [%{message: message, field: :global, action: :ensure_loaded}]}
    end
  end

  @doc false
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

  @doc false
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
