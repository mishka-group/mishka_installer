defmodule MishkaInstaller.Helper.Setting do
  @moduledoc """
  This module offers a number of necessary functions that can be used to access the runtime configuration.
  The owner of the system has the ability to make changes to these parameters, which will then be updated in the database.
  This section was formerly a part of `MishkaCMS`, and the accompanying system is likewise a very straightforward
  one for saving particular settings when the system is being executed.

  **Note**: that the functionality of this section is not restricted to the 'MishkaInstaller' section;
  rather, it can be utilized in other parts of your product.
  """

  use GenServer
  require Logger
  alias MishkaInstaller.Setting, as: DBSetting

  @ets_table :setting_ets_state
  @sync_with_database 100_000
  @re_check_binding_db 10_000

  @doc """
  Start the ETS table `:setting_ets_state` and sync with the settings table in the Postgres database.
  """
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Push your required configs to ETS.
  """
  def push(config) do
    ETS.Set.put!(table(), {String.to_atom(config.name), config.configs})
  end

  @doc """
  Get your required configs from ETS.
  """
  def get(config_name) do
    case ETS.Set.get(table(), String.to_atom(config_name)) do
      {:ok, {_name, config}} -> config
      _ -> nil
    end
  end

  @doc """
  Get All your required configs from ETS.
  """
  def get_all() do
    ETS.Set.to_list!(table())
  end

  def delete(config_name) do
    ETS.Set.delete(table(), String.to_atom(config_name))
  end

  @doc false
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

    table =
      ETS.Set.new!(
        name: @ets_table,
        protection: :public,
        read_concurrency: true,
        write_concurrency: true
      )

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
    sync_with_database()
    Process.send_after(self(), :sync_with_database, @sync_with_database)
    {:noreply, state}
  end

  @impl true
  def handle_info({:setting, :ok, action, repo_data}, state) do
    Logger.warn("Your ETS state of setting is going to be updated")

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

  @doc """
  Sync the ETS config table with your database.
  """
  def sync_with_database() do
    DBSetting.settings()
    |> Enum.map(&push/1)
  end

  defp check_custom_pubsub_loaded(state) do
    custom_pubsub = MishkaInstaller.get_config(:pubsub)

    cond do
      !is_nil(custom_pubsub) && is_nil(Process.whereis(custom_pubsub)) ->
        {:noreply, state, 100}

      true ->
        Process.send_after(self(), :sync_with_database, @re_check_binding_db)
        MishkaInstaller.Setting.subscribe()
        {:noreply, state}
    end
  end

  defp table() do
    case ETS.Set.wrap_existing(@ets_table) do
      {:ok, set} ->
        set

      _ ->
        start_link([])
        table()
    end
  end
end
