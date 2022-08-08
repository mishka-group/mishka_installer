defmodule MishkaInstaller.PluginETS do
  @moduledoc """
  This module provides a series of essential functions for storing plugins on ETS.
  """
  use GenServer
  require Logger
  @ets_table :plugin_ets_state
  @sync_with_database 100_000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
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
    Logger.info("The ETS state of plugin was staretd")
    Process.send_after(self(), :sync_with_database, @sync_with_database)

    {:ok,
     %{
       set:
         ETS.Set.new!(
           name: @ets_table,
           protection: :public,
           read_concurrency: true,
           write_concurrency: true
         )
     }}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.warn("Your ETS state of plugin was restarted by a problem")
    sync_with_database()
  end

  @impl true
  def handle_info(:sync_with_database, state) do
    Logger.info("Plugin ETS state was synced with database")
    Process.send_after(self(), :sync_with_database, @sync_with_database)
    {:noreply, state}
  end

  @doc """
  Storing a plug-in on the ETS table.
  """
  def push(%MishkaInstaller.PluginState{name: name, event: event} = state) do
    ETS.Set.put!(table(), {String.to_atom(name), event, state})
  end

  @doc """
  Getting a plug-in from the ETS table.
  """
  def get(module: name) do
    case ETS.Set.get(table(), String.to_atom(name)) do
      {:ok, {_key, _event, data}} -> data
      _ -> {:error, :get, :not_found}
    end
  end

  @doc """
  Getting all plug-ins from the ETS table.
  """
  def get_all(event: event_name) do
    ETS.Set.match!(table(), {:_, event_name, :"$3"})
    |> Enum.map(&List.first/1)
  end

  @doc """
   - Deleting a plug-in from the ETS table.
   - Deleting plugins from the ETS table based on a specific event.
  """
  def delete(module: module_name) do
    ETS.Set.delete(table(), String.to_atom(module_name))
  end

  def delete(event: event_name) do
    ETS.Set.match_delete(table(), {:_, event_name, :_})
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

  @doc """
  Initializing ETS table with database
  """
  def sync_with_database() do
    MishkaInstaller.Plugin.plugins()
    |> Enum.reject(&(&1.status in [:stopped]))
    |> Enum.map(&push/1)
  end
end
