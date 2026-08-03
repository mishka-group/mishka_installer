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

  ## Statuses and dependencies

  A plugin record carries one of `:registered`, `:started`, `:restarted`, `:stopped` and `:held`.
  Only the last two are meaningful decisions: `:stopped` is an operator's switch and outlives
  restarts and dependency changes, `:held` means "one of my dependencies is not active" and is
  managed by the library.

  Each lifecycle function keeps that distinction:

  - `stop/3` disables a plugin — from any status, including `:held` — and holds everything that
    depends on it, transitively and across events (`sync_dependents/2`).
  - `enable/2` is the only way out of `:stopped`. `restart/3` and `start/3` refuse it, so no reload
    or reset path can silently undo the operator.
  - `start/3`, `restart/3` and `enable/2` release the plugins that were held waiting for them, and a
    plugin whose dependencies are still inactive is stored as `:held` rather than run.
  - `unregister/3` counts as an unsatisfied dependency for whatever depended on the removed plugin.

  Every one of these recompiles the events that changed, so the compiled chain and the stored
  statuses never disagree, and status writes are durable (see `write/3`).

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
  alias MishkaInstaller.Helper.{Extra, UUID}
  import MishkaInstaller.Helper.MnesiaAssistant, only: [er: 1, erl_fields: 4]
  alias MishkaInstaller.Helper.MnesiaAssistant.{Transaction, Query, Table}
  alias MishkaInstaller.Helper.MnesiaAssistant.Error, as: MError
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
    field(:id, UUID.t(), auto: {UUID, :generate}, derives: "validate(uuid)")
    # This type can be used when you want to introduce an plugin name.
    field(:name, module(), enforce: true, derives: "validate(atom)")
    # This type can be used when you want to introduce an event name.
    field(:event, String.t(), enforce: true, derives: "validate(not_empty_string)")
    # This type can be used when you want to introduce a priority of calling an event.
    field(:priority, integer(),
      default: 100,
      derives: "validate(integer, min_len=0, max_len=100)"
    )

    # This type can be used when you want to introduce a status for an event.
    field(:status, status(),
      derives: "validate(enum=Atom[registered::started::stopped::restarted::held])",
      default: :registered
    )

    # This type can be used when you want to introduce an event owner extension.
    field(:extension, atom(), enforce: true, derives: "validate(atom)")

    # This type can be used when you want to introduce a list of modules that an event depend on them.
    field(:depends, list(String.t()), default: [], derives: "validate(list)")
    # This type can be used when you want to introduce an extra data for an event.
    field(:extra, list(map()), default: [], derives: "validate(list)")
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

  ### Re-registering an existing plugin

  This function is an **upsert keyed on the plugin name**: registering an already-registered plugin
  never creates a second row, it reconciles the existing one. The fields declared in code
  (`:priority`, `:extra`, `:depends`) always win, so changing them in a new version of your plugin
  reaches installs that registered with the old values; the runtime-owned fields (`:id`, `:status`,
  `:inserted_at`) are preserved, so a plugin an operator disabled stays disabled across upgrades.

  A changed `:depends` is re-checked for cycles and the status is re-evaluated: the plugin moves to
  `:held` when a new dependency is inactive, and back out of `:held` when its dependencies are
  satisfied.
  """
  @spec register(module(), String.t(), map()) :: error_return | okey_return
  def register(name, event, initial) do
    with {:ok, _module} <- ensure_loaded(name),
         merged <- Map.merge(initial, %{name: name, extension: name.config(:app), event: event}),
         {:ok, struct} <- builder(merged),
         :ok <- no_dependency_cycle(struct.name, struct.depends) do
      case get(:name, name) do
        nil -> insert_registration(struct)
        record -> reconcile_registration(record, struct)
      end
    end
  end

  defp insert_registration(struct) do
    deps_list = allowed_events(struct.depends)

    with {:ok, db_plg} <- write(Map.merge(struct, depends_status(deps_list, struct.status))),
         :ok <- MishkaInstaller.broadcast("event", :register, db_plg) do
      {:ok, db_plg}
    end
  end

  # The plugin is already in the database: keep its runtime state, take the code-declared fields.
  # `priority` and `depends` both change the compiled chain, and a status change may release or hold
  # whatever depends on this plugin, so a real change recompiles and cascades.
  defp reconcile_registration(record, struct) do
    updated_to =
      %{priority: struct.priority, extra: struct.extra, depends: struct.depends}
      |> Map.put(:status, desired_status(%{record | depends: struct.depends}, :db))

    if Enum.all?(updated_to, fn {key, value} -> Map.get(record, key) == value end) do
      MishkaInstaller.broadcast("event", :register, record)
      {:ok, record}
    else
      with {:ok, db_plg} <- write(:id, record.id, updated_to),
           :ok <- MishkaInstaller.broadcast("event", :register, db_plg) do
        EventHandler.do_compile(db_plg.event, :register)
        if db_plg.status != record.status, do: sync_dependents(db_plg.name)
        {:ok, db_plg}
      end
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
  @spec start(:name | :event, module() | String.t(), boolean()) :: error_return | okey_return
  def start(:name, name, queue) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         :ok <- startable?(data.status),
         :ok <- allowed_events?(data.depends),
         {:ok, db_plg} <- write(:id, data.id, %{status: :started}),
         :ok <- EventHandler.do_compile(db_plg.event, :start, queue) do
      sync_dependents(db_plg.name, queue)
      MishkaInstaller.broadcast("event", :start, db_plg)
      {:ok, db_plg}
    end
  end

  def start(:event, event, queue) do
    case get(:event, event) do
      [] ->
        message =
          "There are no plugins in the database that can be started for this event."

        {:error, [%{message: message, field: :global, action: :start_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            case bulk_start(pl_item) do
              {:ok, db_plg} -> acc ++ [db_plg]
              :skip -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :start, queue)
        sync_dependents(Enum.map(sorted_plugins, & &1.name), queue)

        {:ok, sorted_plugins}
    end
  end

  # Bulk start (boot path): an operator's `:stopped` is never overridden, and a plugin whose
  # dependencies are not up yet is recorded as `:held` so it can be released later instead of
  # sitting in `:registered` forever (a dependency on another event may start after this one).
  defp bulk_start(%{status: :stopped}), do: :skip

  defp bulk_start(pl_item) do
    if allowed_events?(pl_item.depends) == :ok do
      case write(:id, pl_item.id, %{status: :started}) do
        {:ok, db_plg} -> {:ok, db_plg}
        _error -> :skip
      end
    else
      if pl_item.status != :held, do: write(:id, pl_item.id, %{status: :held})
      :skip
    end
  end

  @doc """
  This function starts all events, For more information please see `start/2`.
  """
  @spec start(boolean()) :: okey_return() | error_return()
  def start(queue \\ true) do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &start(:event, &1, queue))
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
  @spec restart(:name | :event, module() | String.t(), boolean()) :: error_return | okey_return
  def restart(:name, name, queue) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         :ok <- startable?(data.status),
         :ok <- allowed_events?(data.depends),
         {:ok, db_plg} <- write(:id, data.id, %{status: :restarted}),
         :ok <- EventHandler.do_compile(db_plg.event, :restart, queue) do
      sync_dependents(db_plg.name, queue)
      MishkaInstaller.broadcast("event", :restart, db_plg)
      {:ok, db_plg}
    end
  end

  def restart(:event, event, queue) do
    case get(:event, event) do
      [] ->
        message =
          "There are no plugins in the database that can be started for this event."

        {:error, [%{message: message, field: :global, action: :restart_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            with {:ok, data} <- exist_record?(get(:name, pl_item.name)),
                 :ok <- startable?(data.status),
                 :ok <- allowed_events?(data.depends),
                 {:ok, db_plg} <- write(:id, data.id, %{status: :restarted}) do
              acc ++ [db_plg]
            else
              _ -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :restart, queue)
        sync_dependents(Enum.map(sorted_plugins, & &1.name), queue)

        {:ok, sorted_plugins}
    end
  end

  @doc """
  Re-enables a plugin an operator disabled with `stop/3`. This is the **only** transition out of
  `:stopped`, so no reload, reset or restart path can silently undo a user's decision to switch a
  plugin off.

  If the plugin's dependencies are not active, it is stored as `:held` instead of `:restarted` and
  released automatically as soon as they come back — the call still succeeds, since the operator's
  intent ("this plugin should run") is recorded either way.

  ## Example:

  ```elixir
  stop(:name, TestApp.User.Auth, true)
  enable(TestApp.User.Auth)
  ```
  """
  @spec enable(module(), boolean()) :: error_return | okey_return
  def enable(name, queue \\ true) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         deps_list <- allowed_events(data.depends),
         {:ok, db_plg} <- write(:id, data.id, depends_status(deps_list, :restarted)),
         :ok <- EventHandler.do_compile(db_plg.event, :enable, queue) do
      sync_dependents(db_plg.name, queue)
      MishkaInstaller.broadcast("event", :enable, db_plg)
      {:ok, db_plg}
    end
  end

  @doc """
  This function restarts all events, For more information please see `restart/2`.
  """
  @spec restart(boolean()) :: okey_return() | error_return()
  def restart(queue \\ true) do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &restart(:event, &1, queue))
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
  @spec stop(:name | :event, module() | String.t(), boolean()) :: okey_return() | error_return()
  def stop(:name, name, queue) do
    with {:ok, data} <- exist_record?(get(:name, name)),
         :ok <- stoppable?(data.status),
         {:ok, db_plg} <- write(:id, data.id, %{status: :stopped}),
         :ok <- EventHandler.do_compile(db_plg.event, :stop, queue) do
      sync_dependents(db_plg.name, queue)
      MishkaInstaller.broadcast("event", :stop, db_plg)
      {:ok, db_plg}
    end
  end

  def stop(:event, event, queue) do
    case get(:event, event) do
      [] ->
        message = "There are no plugins in the database that can be stopped for this event."
        {:error, [%{message: message, field: :global, action: :stop_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            with {:ok, data} <- exist_record?(get(:name, pl_item.name)),
                 :ok <- stoppable?(data.status),
                 {:ok, db_plg} <- write(:id, data.id, %{status: :stopped}) do
              acc ++ [db_plg]
            else
              _ -> acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :stop, queue)
        sync_dependents(Enum.map(sorted_plugins, & &1.name), queue)

        {:ok, sorted_plugins}
    end
  end

  @doc """
  This function stops all events, For more information please see `stop/2`.
  """
  @spec stop(boolean()) :: okey_return() | error_return()
  def stop(queue \\ true) do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &stop(:event, &1, queue))
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
  @spec unregister(:name | :event, module() | String.t(), boolean()) ::
          okey_return() | error_return()
  def unregister(:name, name, queue) do
    with {:ok, db_plg} <- delete(:name, name),
         :ok <- EventHandler.do_compile(db_plg.event, :unregister, queue) do
      sync_dependents(db_plg.name, queue)
      MishkaInstaller.broadcast("event", :unregister, db_plg)
      stop_if_alive(name)
      {:ok, db_plg}
    end
  end

  def unregister(:event, event, queue) do
    case get(:event, event) do
      [] ->
        message = "There are no plugins in the database that can be unregistered for this event."
        {:error, [%{message: message, field: :global, action: :unregister_event}]}

      data ->
        sorted_plugins =
          Enum.reduce(data, [], fn pl_item, acc ->
            case delete(:name, pl_item.name) do
              {:ok, db_plg} ->
                stop_if_alive(pl_item.name)
                acc ++ [db_plg]

              _ ->
                acc
            end
          end)
          |> Enum.sort_by(&{&1.priority, &1.name})

        EventHandler.do_compile(event, :unregister, queue)
        sync_dependents(Enum.map(sorted_plugins, & &1.name), queue)

        {:ok, sorted_plugins}
    end
  end

  @doc """
  This function stops all unregisters, For more information please see `unregister/2`.
  """
  @spec unregister(boolean()) :: okey_return() | error_return()
  def unregister(queue \\ true) do
    case group_events() do
      {:ok, events} ->
        sorted_events =
          Enum.map(events, &unregister(:event, &1, queue))
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
  To get all plugins information from Mnesia database.

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
        MishkaInstaller.Helper.MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        []
    end
  end

  @doc """
  To get all plugins or one plugin information from Mnesia database.


  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  # All plugins of an event
  get(:event, "after_login")

  # All plugins of an extension
  get(:extension, :mishka_developer_tools)

  # Get a plugin
  get(:name, TestApp.User.Auth)
  ```
  """
  @spec get(:name | :event | :extension, module() | String.t()) ::
          list(map() | struct()) | map() | struct() | nil
  def get(field, value) when field in [:name, :event, :extension] do
    Transaction.transaction(fn -> Query.index_read(__MODULE__, value, field) end)
    |> case do
      {:atomic, res} ->
        data = MishkaInstaller.Helper.MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])
        if field in [:event, :extension], do: data, else: List.first(data)

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        if field in [:event, :extension], do: [], else: nil
    end
  end

  @doc """
  Like `get(:name, name)` but a **dirty** (non-transactional) index read — a direct ETS lookup with
  no lock or commit overhead. Use only where a slightly stale read is fine (e.g. the background plugin
  status sync), never where you need transactional consistency.
  """
  @spec dirty_get(:name, module()) :: map() | struct() | nil
  def dirty_get(:name, value) do
    :mnesia.dirty_index_read(__MODULE__, value, :name)
    |> MishkaInstaller.Helper.MnesiaAssistant.tuple_to_map(keys(), __MODULE__, [])
    |> List.first()
  end

  @doc """
  To get a plugin information from Mnesia database by id.

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
  @spec get(String.t()) :: map() | struct() | nil
  def get(id) do
    Transaction.transaction(fn -> Query.read(__MODULE__, id) end)
    |> case do
      {:atomic, res} ->
        MishkaInstaller.Helper.MnesiaAssistant.tuple_to_map(res, keys(), __MODULE__, [])
        |> List.first()

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
        nil
    end
  end

  @doc """
  To Add or edit a plugin information from Mnesia database.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  write(%MishkaInstaller.Event.Event{name: TestApp.User.Auth, event: "after_login", extension: :test_app})
  ```
  """
  @spec write(builder_entry) :: error_return | okey_return
  def write(data) do
    case builder(data) do
      {:ok, struct} ->
        values_tuple =
          ([__MODULE__] ++ Enum.map(keys(), &Map.get(struct, &1))) |> List.to_tuple()

        Transaction.durable_transaction(fn -> Query.write(values_tuple) end)
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
  To edit a specific field/fields of a plugin from the Mnesia database.

  > The first input can only be name and ID `[:id, :name]`.

  The record is re-read inside the transaction under a write lock and `updated_to` is merged onto
  the **current** row, so two concurrent transitions of the same plugin cannot clobber each other's
  fields. The transaction is synchronous (see
  `MishkaInstaller.Helper.MnesiaAssistant.Transaction.durable_transaction/1`), so a status change is on
  disk before this function returns and survives an unclean shutdown.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  write(:name, TestApp.User.Auth, %{status: :started})
  ```
  """
  @spec write(atom(), String.t() | module(), map()) :: error_return | okey_return
  def write(field, value, updated_to) when field in [:id, :name] and is_map(updated_to) do
    Transaction.durable_transaction(fn ->
      case locked_read(field, value) do
        nil ->
          :mnesia.abort(:record_not_found)

        data ->
          merged =
            data |> Map.merge(updated_to) |> Map.merge(%{updated_at: Extra.get_unix_time()})

          case builder({:root, merged, :edit}) do
            {:ok, struct} ->
              ([__MODULE__] ++ Enum.map(keys(), &Map.get(struct, &1)))
              |> List.to_tuple()
              |> Query.write()

              struct

            {:error, _} = error ->
              :mnesia.abort(error)
          end
      end
    end)
    |> case do
      {:atomic, struct} ->
        {:ok, struct}

      {:aborted, :record_not_found} ->
        message =
          "The ID of the record you want to update is incorrect or has already been deleted."

        {:error, [%{message: message, field: :global, action: :write}]}

      {:aborted, {:error, _} = error} ->
        error

      {:aborted, reason} ->
        Transaction.transaction_error(reason, __MODULE__, "storing", :global, :database)
    end
  end

  # Reads a single record under a write lock (by id directly, by name via its index then id) and
  # converts it to a struct, or `nil`. Must run inside a transaction.
  defp locked_read(:id, id) do
    :mnesia.read(__MODULE__, id, :write)
    |> MishkaInstaller.Helper.MnesiaAssistant.tuple_to_map(keys(), __MODULE__, [])
    |> List.first()
  end

  defp locked_read(:name, name) do
    case :mnesia.index_read(__MODULE__, name, :name) do
      [record | _] -> locked_read(:id, elem(record, 1))
      _ -> nil
    end
  end

  @doc """
  To get all plugins ids from Mnesia database.



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
  To get all the events defined in the Mnesia database (Only unique items are returned).

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  group_events()
  ```
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
        Transaction.transaction_error(reason, __MODULE__, "reading", :global, :database)
    end
  end

  @doc """
  To delete a plugin from Mnesia database by id or name.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  delete(:name, TestApp.User.Auth)

  delete(:id, "c63aea42-209a-40fb-b5c6-a0d28ee7e25b")
  ```
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
        Transaction.durable_transaction(fn ->
          Query.delete(__MODULE__, Map.get(data, :id), :write)
        end)
        |> case do
          {:atomic, _res} ->
            {:ok, data}

          {:aborted, reason} ->
            Transaction.transaction_error(reason, __MODULE__, "deleting", :global, :database)
        end
    end
  end

  @doc """
  To drop all plugins from Mnesia database.

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
  To check is a plugin unique or not in Mnesia database.

  > It returns `:ok`, or `{:error, reason}`. Note that if the requested plugin does not exist,
  > it means it is unique, and if it is already in the database, it means it is not unique

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  unique(:name, TestApp.User.Auth)
  ```
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
  This function is exactly like `unique/2` function, except that its output is a Boolean.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  unique?(:name, TestApp.User.Auth)
  ```
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

  @doc """
  Returns `:ok` when `depends` introduces no dependency cycle back to `name`, otherwise an error.
  Used by `register/3` to reject plugins that would otherwise stay `:held` forever (e.g. `A → B → A`).
  Built on [`libgraph`](https://hexdocs.pm/libgraph): the candidate's edges are added to the live
  dependency graph and `Graph.is_acyclic?/1` decides.
  """
  @spec no_dependency_cycle(module(), list()) :: :ok | error_return()
  def no_dependency_cycle(name, depends) do
    if Graph.is_acyclic?(dependency_graph(name, depends)) do
      :ok
    else
      message = "Dependency cycle detected: #{inspect(name)} ultimately depends on itself."
      {:error, [%{message: message, field: :depends, action: :register}]}
    end
  end

  @doc """
  The live plugin dependency graph as a [`libgraph`](https://hexdocs.pm/libgraph) `Graph` (one
  `plugin -> dependency` edge per `:depends` entry). Useful for inspecting plugin connections, e.g.
  `Graph.to_dot/1` or `Graph.topsort/1`.
  """
  @spec connections() :: Graph.t()
  def connections(), do: dependency_graph()

  @doc """
  Orders `plugins` (each with `:name`, `:priority`, `:depends`) so a plugin runs **after** the
  plugins it depends on, breaking ties by `{priority, name}`. The set is assumed acyclic (cycles are
  rejected at `register/3`); on a stray cycle it falls back to priority order.
  """
  @spec dependency_order([struct()]) :: [struct()]
  def dependency_order(plugins) do
    order_loop(plugins, MapSet.new(plugins, & &1.name), [])
  end

  defp order_loop([], _pending, acc), do: Enum.reverse(acc)

  defp order_loop(plugins, pending, acc) do
    ready =
      plugins
      |> Enum.filter(fn pl -> Enum.all?(pl.depends, &(not MapSet.member?(pending, &1))) end)
      |> Enum.sort_by(&{&1.priority, &1.name})

    case ready do
      [] -> Enum.reverse(acc) ++ Enum.sort_by(plugins, &{&1.priority, &1.name})
      [next | _] -> order_loop(plugins -- [next], MapSet.delete(pending, next.name), [next | acc])
    end
  end

  @doc """
  Every plugin that declares `name` in its `:depends`, i.e. the reverse dependency edge. Dependencies
  are between **plugins**, so this is global: a dependent registered on another event is included.

  ## Example:

  ```elixir
  dependents(TestApp.User.Auth)
  ```
  """
  @spec dependents(module()) :: list(struct())
  def dependents(name), do: Enum.filter(get(), &(name in &1.depends))

  @doc """
  Re-evaluates everything that depends on `names` after their status changed, and recompiles each
  affected event exactly once. Called by `start/3`, `restart/3`, `stop/3`, `enable/2` and
  `unregister/3`; you only need it directly if you write statuses yourself with `write/3`.

  A dependent whose dependencies are no longer all active is written as `:held`; a `:held` dependent
  whose dependencies are satisfied again is written as `:restarted`. The walk is transitive, so a
  chain `A -> B -> C` (C depends on B, B depends on A) holds and releases as a unit, and it is
  cycle-safe: `names` are never re-evaluated and each dependent is visited once per settling round.

  Two statuses are never touched: `:stopped`, which is an operator decision and must outlive any
  dependency change, and `:registered`, which belongs to a plugin that has not been started yet.

  Returns the list of events that were recompiled.

  ## Example:

  ```elixir
  write(:name, TestApp.User.Auth, %{status: :stopped})
  sync_dependents(TestApp.User.Auth)
  ```
  """
  @spec sync_dependents(module() | list(module()), boolean()) :: list(String.t())
  def sync_dependents(names, queue \\ true) do
    roots = List.wrap(names)
    plugins = get()
    reverse = reverse_depends(plugins)
    affected = transitive_dependents(roots, reverse, MapSet.new(roots), [])

    {_index, changed} =
      settle(affected, Map.new(plugins, &{&1.name, &1}), %{}, length(affected) + 1)

    events = changed |> Map.values() |> Enum.map(& &1.event) |> Enum.uniq()
    Enum.each(events, &EventHandler.do_compile(&1, :re_event, queue))
    events
  end

  # `dependency -> [plugins depending on it]`, built once per cascade from a single table read.
  defp reverse_depends(plugins) do
    Enum.reduce(plugins, %{}, fn pl, acc ->
      Enum.reduce(
        pl.depends,
        acc,
        &Map.update(&2, &1, [pl.name], fn list -> [pl.name | list] end)
      )
    end)
  end

  # Breadth-first over the reverse edges, so a dependent is always evaluated after the plugin it
  # depends on. `seen` starts as the roots, which both skips them and bounds a cyclic graph.
  defp transitive_dependents([], _reverse, _seen, acc), do: acc

  defp transitive_dependents([name | rest], reverse, seen, acc) do
    next = Map.get(reverse, name, []) |> Enum.reject(&MapSet.member?(seen, &1))
    seen = Enum.reduce(next, seen, &MapSet.put(&2, &1))
    transitive_dependents(rest ++ next, reverse, seen, acc ++ next)
  end

  # A single pass cannot settle a diamond (a plugin reached before one of its other dependencies was
  # updated), so passes repeat while anything changes, bounded by the size of the affected set.
  defp settle(names, index, changed, rounds) when rounds > 0 do
    {index, changed, dirty?} =
      Enum.reduce(names, {index, changed, false}, fn name, {index, changed, dirty?} ->
        record = Map.get(index, name)
        desired = if is_nil(record), do: nil, else: desired_status(record, index)

        if is_nil(record) or desired == record.status do
          {index, changed, dirty?}
        else
          case write(:id, record.id, %{status: desired}) do
            {:ok, updated} ->
              {Map.put(index, name, updated), Map.put(changed, name, updated), true}

            _error ->
              {index, changed, dirty?}
          end
        end
      end)

    if dirty?, do: settle(names, index, changed, rounds - 1), else: {index, changed}
  end

  defp settle(_names, index, changed, _rounds), do: {index, changed}

  # The status a plugin should hold given its dependencies, looked up either in a cascade's snapshot
  # or, with `:db`, in the database.
  defp desired_status(%{status: :stopped}, _index), do: :stopped

  defp desired_status(%{status: :registered}, _index), do: :registered

  defp desired_status(%{status: status, depends: depends}, index) do
    cond do
      !depends_satisfied?(depends, index) -> :held
      status == :held -> :restarted
      true -> status
    end
  end

  defp depends_satisfied?(depends, :db), do: allowed_events?(depends) == :ok

  defp depends_satisfied?(depends, index),
    do: Enum.all?(depends, &active?(Map.get(index, &1)))

  defp active?(%{status: status}), do: status in [:started, :restarted]

  defp active?(_record), do: false

  defp dependency_graph(extra_name \\ nil, extra_depends \\ []) do
    candidates = Enum.reject(get(), &(&1.name == extra_name))

    candidates =
      if(extra_name,
        do: candidates ++ [%{name: extra_name, depends: extra_depends}],
        else: candidates
      )

    Enum.reduce(candidates, Graph.new(), fn pl, graph ->
      Enum.reduce(pl.depends, Graph.add_vertex(graph, pl.name), fn dep, acc ->
        Graph.add_edge(acc, pl.name, dep)
      end)
    end)
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

  # `:stopped` is the operator's decision and only `enable/2` may leave it; `:held` may be started,
  # its dependencies are re-checked by `allowed_events?/1` right after.
  defp startable?(:stopped) do
    message = "This plugin is stopped, use `enable/2` to switch it back on."
    {:error, [%{message: message, field: :global, action: :plugin_status}]}
  end

  defp startable?(_status), do: :ok

  # Stopping is allowed from any status, including `:held`, but is not repeatable.
  defp stoppable?(:stopped) do
    message = "This plugin is already stopped."
    {:error, [%{message: message, field: :global, action: :plugin_status}]}
  end

  defp stoppable?(_status), do: :ok

  defp exist_record?(nil) do
    message =
      "The ID of the record you want is incorrect or has already been deleted."

    {:error, [%{message: message, field: :global, action: :exist_record?}]}
  end

  defp exist_record?(data), do: {:ok, data}

  # Stop a plugin's GenServer only if it is actually running, so unregister can't crash on a plugin
  # whose process is already down.
  defp stop_if_alive(name) do
    if Process.whereis(name), do: GenServer.stop(name, :normal), else: :ok
  end
end
