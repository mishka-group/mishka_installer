defmodule MishkaInstaller.PluginETS do
  @moduledoc """

    ## ETS part to optimization state instead of dynamic supervisor and Genserver
    `public` — Read/Write available to all processes.
    `protected` — Read available to all processes. Only writable by owner process. This is the default.
    `private` — Read/Write limited to owner process.

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

    ### Refs
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
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    Logger.warn("The ETS state of plugin was staretd")
    {:ok, %{set: ETS.Set.new!(name: @ets_table, protection: :public, read_concurrency: true, write_concurrency: true)}}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.warn("Your ETS state of plugin was restarted by a problem")
  end

  def push(%MishkaInstaller.PluginState{name: name, event: event} = state) do
    ETS.Set.put!(table(), {String.to_atom(name), event, state})
  end

  def table() do
    case ETS.Set.wrap_existing(@ets_table) do
      {:ok, set} -> set
      _ ->
        start_link([])
        table()
    end
  end
end
