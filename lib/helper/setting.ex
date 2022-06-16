defmodule MishkaInstaller.Helper.Setting do
  use GenServer
  require Logger
  @ets_table :setting_ets_state
  @sync_with_database 100_000
  @re_check_binding_db 10_000
  alias MishkaInstaller.Setting, as: DBSetting

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def push(config) do
    ETS.Set.put!(table(), {String.to_atom(config.name), config.configs})
  end

  def get(config_name) do
    case ETS.Set.get(table(), String.to_atom(config_name)) do
      {:ok, {_name, config}} -> config
      _ -> nil
    end
  end

  def get_all() do
    ETS.Set.match!(table(), {:"$1", :"$2"})
    |> Enum.map(&List.first/1)
  end

  def delete(config_name) do
    ETS.Set.delete(table(), String.to_atom(config_name))
  end

  def child_spec(process_name) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [process_name]},
      restart: :transient,
      max_restarts: 4
    }
  end

  @impl true
  def init(_state) do
    Logger.info("The ETS state of settings was staretd")
    Process.send_after(self(), :sync_with_database, @sync_with_database)
    table = ETS.Set.new!(name: @ets_table, protection: :public, read_concurrency: true, write_concurrency: true)
    {:ok, %{set: table}, {:continue, :sync_with_database}}
  end

  @impl true
  def handle_continue(:sync_with_database, state) do
    check_custom_pubsub_loaded(state)
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.info("We are waiting for your custom pubsub is loaded")
    check_custom_pubsub_loaded(state)
  end

  @impl true
  def handle_info(:sync_with_database, state) do
    Logger.info("Setting ETS state was synced with database")
    Process.send_after(self(), :sync_with_database, @sync_with_database)
    {:noreply, state}
  end

  @impl true
  def handle_info({:setting, :ok, action, repo_data}, state) do
    case action do
      :delete -> delete(repo_data.name)
      _ -> push(repo_data)
    end
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.warn("Your ETS state of setting was restarted by a problem")
  end

  def sync_with_database() do
    DBSetting.settings()
    |> push()
  end

  defp check_custom_pubsub_loaded(state) do
    custom_pubsub = MishkaInstaller.get_config(:pubsub)
    cond do
      !is_nil(custom_pubsub) && is_nil(Process.whereis(custom_pubsub)) -> {:noreply, state, 100}
      true ->
        Process.send_after(self(), :sync_with_database, @re_check_binding_db )
        MishkaInstaller.Setting.subscribe()
        {:noreply, state}
    end
  end

  defp table() do
    case ETS.Set.wrap_existing(@ets_table) do
      {:ok, set} -> set
      _ ->
        start_link([])
        table()
    end
  end
end
