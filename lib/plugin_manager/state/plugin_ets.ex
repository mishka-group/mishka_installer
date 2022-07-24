defmodule MishkaInstaller.PluginETS do
  @moduledoc """
    ETS part to optimization state instead of dynamic supervisor and Genserver

    1. `public` — Read/Write available to all processes.
    2. `protected` — Read available to all processes. Only writable by owner process. This is the default.
    3. `private` — Read/Write limited to owner process.

    #### Essential functions in ETS

    1.  :ets.new
    ```elixir
    :ets.new(@tab, [:set, :named_table, :public, read_concurrency: true, write_concurrency: true])
    ```
    2.  :ets.insert
    3.  :ets.insert_new
    4.  :ets.lookup
    5.  :ets.match
    6.  :ets.match_object
    7.  :ets.select
    8.  :ets.fun2ms
    9.  :ets.delete
    10. :dets.open_file
    11. :ets.update_counter
    12. :ets.delete_all_objects
    13. :ets.tab2list - to spy on the data in the table
    14. :ets.update_counter
    15. :ets.all
    16. :ets.info

    ### Reference

    * https://www.erlang.org/doc/man/ets.html
    * https://dockyard.com/blog/2017/05/19/optimizing-elixir-and-phoenix-with-ets
    * https://learnyousomeerlang.com/ets
    * https://elixir-lang.org/getting-started/mix-otp/ets.html
    * https://elixirschool.com/en/lessons/storage/ets
    * https://github.com/TheFirstAvenger/ets
  """
  use GenServer
  require Logger
  @ets_table :plugin_ets_state
  @sync_with_database 100_000

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
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

  def push(%MishkaInstaller.PluginState{name: name, event: event} = state) do
    ETS.Set.put!(table(), {String.to_atom(name), event, state})
  end

  def get(module: name) do
    case ETS.Set.get(table(), String.to_atom(name)) do
      {:ok, {_key, _event, data}} -> data
      _ -> {:error, :get, :not_found}
    end
  end

  def get_all(event: event_name) do
    ETS.Set.match!(table(), {:_, event_name, :"$3"})
    |> Enum.map(&List.first/1)
  end

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

  def sync_with_database() do
    MishkaInstaller.Plugin.plugins()
    |> Enum.reject(&(&1.status in [:stopped]))
    |> Enum.map(&push/1)
  end
end
