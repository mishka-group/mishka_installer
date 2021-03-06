defmodule MishkaInstaller.Hook do
  alias MishkaInstaller.PluginState
  alias MishkaInstaller.PluginStateDynamicSupervisor, as: PSupervisor
  alias MishkaInstaller.Plugin
  alias MishkaInstaller.PluginETS
  @allowed_fields [:name, :event, :priority, :status, :depend_type, :depends, :extra, :id]

  @type event() :: String.t()
  @type plugin() :: event()

  @spec register([{:depends, :force} | {:event, MishkaInstaller.PluginState.t()}]) ::
          {:error, :register, any} | {:ok, :register, :activated | :force}
  def register(event: %PluginState{} = event) do
    extra = (event.extra || []) ++ [%{operations: :hook}, %{fun: :register}]

    register_status =
      with {:ok, :ensure_event, _msg} <- ensure_event(event, :debug),
           {:error, :get_record_by_field, :plugin} <- Plugin.show_by_name("#{event.name}"),
           {:ok, :add, :plugin, _record_info} <- Plugin.create(event, @allowed_fields) do
        # Create a Genserver with DynamicSupervisor
        PluginState.push_call(event)
        # Save all event info into ETS, Existed-key is overwritten
        PluginETS.push(event)
        {:ok, :register, :activated}
      else
        {:error, :ensure_event, %{errors: check_data}} ->
          MishkaInstaller.plugin_activity(
            "add",
            Map.merge(event, %{extra: extra}),
            "high",
            "error"
          )

          {:error, :register, check_data}

        {:ok, :get_record_by_field, :plugin, record_info} ->
          # Create a Genserver with DynamicSupervisor
          PluginState.push_call(plugin_state_struct(record_info))
          # Save all event info into ETS, Existed-key is overwritten
          PluginETS.push(plugin_state_struct(record_info))
          {:ok, :register, :activated}

        {:error, :add, :plugin, repo_error} ->
          MishkaInstaller.plugin_activity(
            "add",
            Map.merge(event, %{extra: extra}),
            "high",
            "error"
          )

          {:error, :register, repo_error}
      end

    register_status
  end

  def register(event: %PluginState{} = event, depends: :force) do
    # Create a Genserver with DynamicSupervisor
    PluginState.push_call(event)
    # Save all event info into ETS
    PluginETS.push(event)
    {:ok, :register, :force}
  end

  @spec start([{:depends, :force} | {:event, event()} | {:module, plugin()}]) ::
          list | {:error, :start, any()} | {:ok, :start, :force | String.t()}
  def start(module: module_name) do
    with {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}"),
         {:ok, :ensure_event, _msg} <- ensure_event(plugin_state_struct(record_info), :debug) do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))

      {:ok, :start,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module's status was changed"
       )}
    else
      {:error, :get_record_by_field, :plugin} ->
        {:error, :start,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}

      {:error, :ensure_event, %{errors: check_data}} ->
        {:error, :start, check_data}
    end
  end

  def start(module: module_name, depends: :force) do
    with {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}") do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info) |> Map.merge(%{status: :started}))
      {:ok, :start, :force}
    else
      {:error, :get_record_by_field, :plugin} ->
        {:error, :start,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}
    end
  end

  def start(event: event) do
    Plugin.plugins(event: event)
    |> Enum.map(&start(module: &1.name))
  end

  def start(event: event, depends: :force) do
    Plugin.plugins(event: event)
    |> Enum.map(&start(module: &1.name, depends: :force))
  end

  @spec restart([{:depends, :force} | {:event, event()} | {:module, plugin()}]) ::
          list | {:error, :restart, any()} | {:ok, :restart, String.t()}
  def restart(module: module_name) do
    with {:ok, :delete} <- PluginState.delete(module: module_name),
         {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}"),
         {:ok, :ensure_event, _msg} <- ensure_event(plugin_state_struct(record_info), :debug) do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info))

      {:ok, :restart,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module concerned was restarted"
       )}
    else
      {:error, :delete, :not_found} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the state."
         )}

      {:error, :ensure_event, %{errors: check_data}} ->
        {:error, :restart, check_data}

      {:error, :get_record_by_field, :plugin} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}
    end
  end

  def restart(module: module_name, depends: :force) do
    with {:ok, :delete} <- PluginState.delete(module: module_name),
         {:ok, :get_record_by_field, :plugin, record_info} <-
           Plugin.show_by_name("#{module_name}") do
      # Create a Genserver with DynamicSupervisor
      PluginState.push_call(plugin_state_struct(record_info))
      # Save all event info into ETS, Existed-key is overwritten
      PluginETS.push(plugin_state_struct(record_info))

      {:ok, :restart,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module concerned was restarted"
       )}
    else
      {:error, :delete, :not_found} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the state."
         )}

      {:error, :get_record_by_field, :plugin} ->
        {:error, :restart,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in the database."
         )}
    end
  end

  def restart(event: event_name) do
    Plugin.plugins(event: event_name)
    |> Enum.map(&restart(module: &1.name))
  end

  def restart(event: event_name, depends: :force) do
    Plugin.plugins(event: event_name)
    |> Enum.map(&restart(module: &1.name, depends: :force))
  end

  def restart(depends: :force) do
    Plugin.plugins()
    |> Enum.map(&restart(module: &1.name, depends: :force))
  end

  def restart() do
    Plugin.plugins()
    |> Enum.map(&restart(module: &1.name))
  end

  @spec stop([{:event, event()} | {:module, plugin()}]) ::
          list | {:error, :stop, String.t()} | {:ok, :stop, String.t()}
  def stop(module: module_name) do
    case PluginState.stop(module: module_name) do
      {:ok, :stop} ->
        PluginETS.delete(module: module_name)

        {:ok, :stop,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned was stopped"
         )}

      {:error, :stop, :not_found} ->
        {:error, :stop,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist in database."
         )}
    end
  end

  def stop(event: event_name) do
    PSupervisor.running_imports(event_name)
    |> Enum.map(&stop(module: &1.id))
  end

  @spec delete([{:event, event()} | {:module, plugin()}]) ::
          list | {:error, :delete, String.t()} | {:ok, :delete, String.t()}
  def delete(module: module_name) do
    case PluginState.delete(module: module_name) do
      {:ok, :delete} ->
        PluginETS.delete(module: module_name)

        {:ok, :delete,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module's state (%{name}) was deleted",
           name: module_name
         )}

      {:error, :delete, :not_found} ->
        {:error, :delete,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned (%{name}) doesn't exist in the state.",
           name: module_name
         )}
    end
  end

  def delete(event: event_name) do
    PSupervisor.running_imports(event_name)
    |> Enum.map(&delete(module: &1.id))
  end

  @spec unregister([{:event, event()} | {:module, plugin()}]) ::
          list | {:error, :unregister, any} | {:ok, :unregister, Stream.timer()}
  def unregister(module: module_name) do
    with {:ok, :delete, _msg} <- delete(module: module_name),
         {:ok, :get_record_by_field, :plugin, record_info} <- Plugin.show_by_name(module_name),
         {:ok, :delete, :plugin, _} <- Plugin.delete(record_info.id) do
      Plugin.delete_plugins(module_name)

      {:ok, :unregister,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The module concerned (%{name}) and its dependencies were unregister",
         name: module_name
       )}
    else
      {:error, :delete, msg} ->
        {:error, :unregister, msg}

      {:error, :get_record_by_field, :plugin} ->
        {:error, :unregister,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The %{name} module doesn't exist in the database.",
           name: module_name
         )}

      {:error, :delete, status, _error_tag}
      when status in [:uuid, :get_record_by_id, :forced_to_delete] ->
        {:error, :unregister,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "There is a problem to find or delete the record in the database %{status}, module: %{name}",
           status: status,
           name: module_name
         )}

      {:error, :delete, :plugin, repo_error} ->
        {:error, :unregister, repo_error}
    end
  end

  def unregister(event: event_name) do
    Plugin.plugins(event: event_name)
    |> Enum.map(&unregister(module: &1.name))
  end

  def call(event: event_name, state: state, operation: :no_return) do
    call(event: event_name, state: state)
    state
  end

  def call(event: event_name, state: state) do
    call_output =
      PluginETS.get_all(event: event_name)
      |> sorted_plugins()
      |> run_plugin_state({:reply, state})

    if !is_nil(Map.get(state, :private)),
      do: Map.merge(call_output, %{private: state.private}),
      else: call_output
  rescue
    _e -> state
  end

  defp run_plugin_state([], {:reply, state}), do: state

  defp run_plugin_state(_plugins, {:reply, :halt, state}), do: state

  defp run_plugin_state([h | t], {:reply, state}) do
    new_state = apply(String.to_atom("Elixir.#{h.name}"), :call, [state])
    run_plugin_state(t, new_state)
  end

  defp sorted_plugins(plugins) do
    plugins
    |> Enum.map(fn event ->
      case ensure_event(event, :debug) do
        {:error, :ensure_event, %{errors: _check_data}} ->
          extra = event.extra ++ [%{operations: :hook}, %{fun: :call}]

          MishkaInstaller.plugin_activity(
            "read",
            Map.merge(event, %{extra: extra}),
            "high",
            "error"
          )

          []

        {:ok, :ensure_event, _msg} ->
          %{name: event.name, priority: event.priority, status: event.status}
      end
    end)
    |> Enum.filter(&(&1 != [] and &1.status == :started))
    |> Enum.sort_by(fn item -> {item.priority, item.name} end)
  end

  @spec ensure_event?(PluginState.t()) :: boolean
  def ensure_event?(%PluginState{depend_type: :hard, depends: depends} = event) do
    check_data = check_dependencies(depends, event.name)

    Enum.any?(check_data, fn {status, _error_atom, _event, _msg} -> status == :error end)
    |> case do
      true -> false
      false -> true
    end
  end

  def ensure_event?(%PluginState{} = _event), do: true

  @spec ensure_event(PluginState.t(), :debug) ::
          {:error, :ensure_event, %{errors: list}} | {:ok, :ensure_event, String.t()}
  def ensure_event(%PluginState{depend_type: :hard, depends: depends} = event, :debug)
      when depends != [] do
    check_data = check_dependencies(depends, event.name)

    Enum.any?(check_data, fn {status, _error_atom, _event, _msg} -> status == :error end)
    |> case do
      true ->
        {:error, :ensure_event, %{errors: check_data}}

      false ->
        {:ok, :ensure_event,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The modules concerned are activated"
         )}
    end
  end

  def ensure_event(%PluginState{depend_type: :hard} = _event, :debug),
    do:
      {:ok, :ensure_event,
       Gettext.dgettext(
         MishkaInstaller.gettext(),
         "mishka_installer",
         "The modules concerned are activated"
       )}

  def ensure_event(%PluginState{} = _event, :debug),
    do: {:ok, :ensure_event, "The modules concerned are activated"}

  defp check_dependencies(depends, event_name) do
    Enum.map(depends, fn evn ->
      with {:ensure_loaded, true} <-
             {:ensure_loaded, Code.ensure_loaded?(String.to_atom("Elixir.#{evn}"))},
           plugin_state <- PluginETS.get(module: evn),
           {:plugin_state?, true, _state} <-
             {:plugin_state?, is_struct(plugin_state), plugin_state},
           {:activated_plugin, true, _state} <-
             {:activated_plugin, Map.get(plugin_state, :status) == :started, plugin_state} do
        {:ok, :ensure_event, evn, "The module concerned is activated"}
      else
        {:ensure_loaded, false} ->
          {:error, :ensure_loaded, evn,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "The module concerned doesn't exist."
           )}

        {:plugin_state?, false, _state} ->
          {:error, :plugin_state?, evn,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "The event concerned doesn't exist in state."
           )}

        {:activated_plugin, false, _state} ->
          {:error, :activated_plugin, evn,
           Gettext.dgettext(
             MishkaInstaller.gettext(),
             "mishka_installer",
             "The event concerned is not activated."
           )}
      end
    end) ++
      [string_ensure_loaded(event_name)]
  end

  defp string_ensure_loaded(event_name) do
    case Code.ensure_loaded?(String.to_atom("Elixir.#{event_name}")) do
      true ->
        {:ok, :ensure_event, event_name,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned is activated"
         )}

      false ->
        {:error, :ensure_loaded, event_name,
         Gettext.dgettext(
           MishkaInstaller.gettext(),
           "mishka_installer",
           "The module concerned doesn't exist."
         )}
    end
  end

  defp plugin_state_struct(output) do
    %PluginState{
      name: output.name,
      event: output.event,
      priority: output.priority,
      status: output.status,
      depend_type: output.depend_type,
      depends: Map.get(output, :depends) || [],
      extra: Map.get(output, :extra) || [],
      parent_pid: Map.get(output, :parent_pid)
    }
  end

  defmacro __using__(opts) do
    quote(bind_quoted: [opts: opts]) do
      import MishkaInstaller.Hook
      use GenServer, restart: :transient
      require Logger
      alias MishkaInstaller.{PluginState, Hook}
      module_selected = Keyword.get(opts, :module)
      initial_entry = Keyword.get(opts, :initial)
      behaviour = Keyword.get(opts, :behaviour)
      event = Keyword.get(opts, :event)

      @ref event
      @behaviour behaviour

      # Start registering with Genserver and set this in application file of MishkaInstaller
      def start_link(_args) do
        GenServer.start_link(unquote(module_selected), %{id: "#{unquote(module_selected)}"},
          name: unquote(module_selected)
        )
      end

      def init(state) do
        if Mix.env() != :test, do: {:ok, state, 300}, else: {:ok, state, 3000}
      end

      # This part helps us to wait for database and completing PubSub either
      def handle_info(:timeout, state) do
        cond do
          !is_nil(MishkaInstaller.get_config(:pubsub)) &&
              is_nil(Process.whereis(MishkaInstaller.get_config(:pubsub))) ->
            {:noreply, state, 100}

          !is_nil(MishkaInstaller.get_config(:pubsub)) ->
            unquote(module_selected).initial(unquote(initial_entry))
            {:noreply, state}

          true ->
            unquote(module_selected).initial(unquote(initial_entry))
            {:noreply, state}
        end
      end
    end
  end
end
