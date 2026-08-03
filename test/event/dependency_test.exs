# Plain plugin modules (only `call/1` is needed to be compiled into an event chain); each one
# stamps its own name on the state so a chain can be read back from `Hook.call/3`.
defmodule MishkaInstallerTest.Event.DependencyTest.Root do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.DependencyTest.RootTwo do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.DependencyTest.Mid do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.DependencyTest.Sibling do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.DependencyTest.Leaf do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.DependencyTest.Diamond do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, Map.update(state, :ran, [__MODULE__], &(&1 ++ [__MODULE__]))}
end

defmodule MishkaInstallerTest.Event.DependencyTest.CycleA do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.DependencyTest.CycleB do
  @moduledoc false
  def config(:app), do: :mishka_installer
  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.DependencyTest do
  use ExUnit.Case, async: false

  alias MishkaInstaller.Event.{Event, EventHandler, Hook, ModuleStateCompiler}

  alias MishkaInstallerTest.Event.DependencyTest.{
    Root,
    RootTwo,
    Mid,
    Sibling,
    Leaf,
    Diamond,
    CycleA,
    CycleB
  }

  @root_evt "dep_root_evt"
  @mid_evt "dep_mid_evt"
  @leaf_evt "dep_leaf_evt"
  @diamond_evt "dep_diamond_evt"

  setup do
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-dependency-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Event]
    )

    on_exit(fn ->
      for name <- [MishkaInstaller.MnesiaRepo, EventHandler] do
        pid = Process.whereis(name)
        if is_pid(pid) and Process.alive?(pid), do: GenServer.stop(name)
      end

      for event <- [@root_evt, @mid_evt, @leaf_evt, @diamond_evt],
          do: ModuleStateCompiler.purge(event)

      File.rm_rf!(tmp)
    end)

    MishkaInstaller.subscribe("mnesia")
    MishkaInstaller.subscribe("event")
    start_supervised!(EventHandler)
    start_supervised!(MishkaInstaller.MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    :ok
  end

  ###################################################################################
  ################### (▰˘◡˘▰) Cascade on disable (▰˘◡˘▰) ######################
  ###################################################################################
  describe "stopping a dependency ===>" do
    test "holds its dependent on another event and drops it from that event's chain" do
      tree()

      assert chain(@mid_evt) == [Mid, Sibling]

      {:ok, stopped} = Event.stop(:name, Root, false)

      assert stopped.status == :stopped
      assert status(Mid) == :held
      assert status(Sibling) == :started
      assert chain(@mid_evt) == [Sibling]
      assert Hook.call(@mid_evt, %{}).ran == [Sibling]
    end

    test "holds a whole nested chain, and releasing the dependency releases all of it" do
      tree()

      {:ok, _} = Event.stop(:name, Root, false)

      assert status(Mid) == :held
      assert status(Leaf) == :held
      assert chain(@leaf_evt) == []

      {:ok, enabled} = Event.enable(Root, false)

      assert enabled.status == :restarted
      assert status(Mid) == :restarted
      assert status(Leaf) == :restarted
      assert chain(@mid_evt) == [Mid, Sibling]
      assert chain(@leaf_evt) == [Leaf]
    end

    test "leaves a dependent the operator stopped by hand stopped when it comes back" do
      tree()

      {:ok, _} = Event.stop(:name, Mid, false)
      {:ok, _} = Event.stop(:name, Root, false)
      {:ok, _} = Event.enable(Root, false)

      assert status(Root) == :restarted
      assert status(Mid) == :stopped
      assert status(Leaf) == :held
      refute Mid in chain(@mid_evt)
    end

    test "does not touch the plugins it depends on or their other dependents" do
      tree()

      {:ok, _} = Event.stop(:name, Mid, false)

      assert status(Root) == :started
      assert status(Diamond) == :started
      assert status(Sibling) == :started
      assert status(Leaf) == :held
      assert chain(@diamond_evt) == [Diamond]
    end

    test "unregistering a dependency holds its dependents like stopping it does" do
      tree()

      {:ok, _} = Event.unregister(:name, Root, false)

      assert is_nil(Event.get(:name, Root))
      assert status(Mid) == :held
      assert status(Leaf) == :held
      assert status(Diamond) == :held
    end

    test "a plugin held by a dependency can still be stopped by the operator" do
      tree()

      {:ok, _} = Event.stop(:name, Root, false)
      assert status(Mid) == :held

      {:ok, stopped} = Event.stop(:name, Mid, false)
      assert stopped.status == :stopped

      {:ok, _} = Event.enable(Root, false)
      assert status(Mid) == :stopped
    end
  end

  describe "a plugin with more than one dependency ===>" do
    test "stays held until every one of them is active again" do
      tree()

      {:ok, _} = Event.stop(:name, Root, false)
      {:ok, _} = Event.stop(:name, RootTwo, false)
      assert status(Diamond) == :held

      {:ok, _} = Event.enable(Root, false)
      assert status(Diamond) == :held

      {:ok, _} = Event.enable(RootTwo, false)
      assert status(Diamond) == :restarted
      assert chain(@diamond_evt) == [Diamond]
    end

    test "is held by either dependency on its own" do
      tree()

      {:ok, _} = Event.stop(:name, RootTwo, false)
      assert status(Diamond) == :held
      assert status(Mid) == :started

      {:ok, _} = Event.enable(RootTwo, false)
      assert status(Diamond) == :restarted
    end
  end

  describe "dependency graph reads ===>" do
    test "dependents/1 crosses events and only reports direct dependents" do
      tree()

      assert Enum.sort(Enum.map(Event.dependents(Root), & &1.name)) == Enum.sort([Mid, Diamond])
      assert Enum.map(Event.dependents(Mid), & &1.name) == [Leaf]
      assert Event.dependents(Leaf) == []
    end

    test "a dependency cycle in stored records settles instead of looping forever" do
      tree()
      plugin(CycleA, @leaf_evt, depends: [Root, CycleB])
      plugin(CycleB, @leaf_evt, depends: [CycleA])

      task = Task.async(fn -> Event.stop(:name, Root, false) end)

      assert {:ok, _} = Task.await(task, 5000)
      assert status(CycleA) == :held
      assert status(CycleB) == :held
    end
  end

  ###################################################################################
  ################## (▰˘◡˘▰) Compiled chain freshness (▰˘◡˘▰) #################
  ###################################################################################
  describe "recompiling after a change ===>" do
    test "removing one plugin of a multi-plugin event rebuilds the chain immediately" do
      plugin(Root, @mid_evt, priority: 10)
      plugin(Sibling, @mid_evt, priority: 20)
      plugin(Mid, @mid_evt, priority: 30)
      compile(@mid_evt)

      assert chain(@mid_evt) == [Root, Sibling, Mid]

      {:ok, _} = Event.stop(:name, Sibling, false)

      assert chain(@mid_evt) == [Root, Mid]
      assert Hook.call(@mid_evt, %{}).ran == [Root, Mid]
    end

    test "an unchanged event is not rebuilt again" do
      plugin(Root, @root_evt)
      compile(@root_evt)
      assert_receive %{status: :purge_create, data: @root_evt}

      compile(@root_evt)
      refute_receive %{status: :purge_create, data: @root_evt}, 200
    end

    test "a settled graph cascades no writes and recompiles nothing" do
      tree()

      assert Event.sync_dependents(Root, false) == []
      assert Event.sync_dependents([Root, RootTwo, Mid], false) == []
      assert status(Mid) == :started
    end
  end

  ###################################################################################
  ###################### (▰˘◡˘▰) Status guards (▰˘◡˘▰) ########################
  ###################################################################################
  describe "operator transitions ===>" do
    test "restart never re-enables a stopped plugin, enable is the only way back" do
      plugin(Root, @root_evt)

      {:ok, _} = Event.stop(:name, Root, false)

      assert {:error, [%{action: :plugin_status}]} = Event.restart(:name, Root, false)
      assert status(Root) == :stopped

      assert {:ok, %{status: :restarted}} = Event.enable(Root, false)
    end

    test "a failed restart does not leave a status behind" do
      plugin(Mid, @mid_evt, depends: [MishkaInstallerTest.Event.DependencyTest.Ghost])

      assert {:error, [%{action: :hold_statuses}]} = Event.restart(:name, Mid, false)
      assert status(Mid) == :started
    end

    test "enable records the operator's intent as :held while a dependency is down" do
      tree()

      {:ok, _} = Event.stop(:name, Root, false)
      {:ok, _} = Event.stop(:name, Mid, false)

      assert {:ok, %{status: :held}} = Event.enable(Mid, false)

      {:ok, _} = Event.enable(Root, false)
      assert status(Mid) == :restarted
    end

    test "stopping an already stopped plugin is rejected" do
      plugin(Root, @root_evt)

      {:ok, _} = Event.stop(:name, Root, false)
      assert {:error, [%{action: :plugin_status}]} = Event.stop(:name, Root, false)
    end

    test "a bulk start releases what it can and holds what it cannot, never touching :stopped" do
      plugin(Root, @root_evt, status: :registered)
      plugin(RootTwo, @root_evt, status: :stopped)
      plugin(Mid, @mid_evt, status: :registered, depends: [Root])
      plugin(Diamond, @diamond_evt, status: :registered, depends: [Root, RootTwo])

      {:ok, _} = Event.start(false)

      assert status(Root) == :started
      assert status(RootTwo) == :stopped
      assert status(Mid) in [:started, :restarted]
      assert status(Diamond) == :held
      assert chain(@mid_evt) == [Mid]
      assert chain(@diamond_evt) == []
    end
  end

  ###################################################################################
  ##################### (▰˘◡˘▰) Registration (▰˘◡˘▰) ##########################
  ###################################################################################
  describe "re-registering a plugin ===>" do
    test "keeps one row and takes the code-declared fields over the stored ones" do
      {:ok, first} = Event.register(Root, @root_evt, %{priority: 10, extra: [%{feature: :old}]})

      {:ok, _} = Event.stop(:name, Root, false)

      {:ok, second} = Event.register(Root, @root_evt, %{priority: 50, extra: [%{feature: :new}]})

      assert length(Event.get()) == 1
      assert second.id == first.id
      assert second.inserted_at == first.inserted_at
      assert second.priority == 50
      assert second.extra == [%{feature: :new}]
      assert second.status == :stopped
    end

    test "re-evaluates the status when the code changes depends" do
      plugin(RootTwo, @root_evt, status: :stopped)

      {:ok, held} = Event.register(Mid, @mid_evt, %{depends: [RootTwo]})
      assert held.status == :held

      {:ok, released} = Event.register(Mid, @mid_evt, %{depends: []})
      assert released.status == :restarted
    end

    test "a re-registration that changes nothing writes nothing" do
      {:ok, first} = Event.register(Root, @root_evt, %{priority: 10})
      {:ok, second} = Event.register(Root, @root_evt, %{priority: 10})

      assert second.updated_at == first.updated_at
    end
  end

  ###################################################################################
  ######################### (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ###################################################################################
  # Root <- Mid <- Leaf (each on its own event), Sibling sharing Mid's event, and Diamond
  # depending on both Root and RootTwo. Every record starts active and every event is compiled.
  defp tree do
    plugin(Root, @root_evt)
    plugin(RootTwo, @root_evt, priority: 20)
    plugin(Mid, @mid_evt, priority: 10, depends: [Root])
    plugin(Sibling, @mid_evt, priority: 20)
    plugin(Leaf, @leaf_evt, depends: [Mid])
    plugin(Diamond, @diamond_evt, depends: [Root, RootTwo])

    for event <- [@root_evt, @mid_evt, @leaf_evt, @diamond_evt], do: compile(event)
  end

  defp plugin(name, event, opts \\ []) do
    {:ok, record} =
      Event.write(%{
        name: name,
        event: event,
        extension: :mishka_installer,
        depends: Keyword.get(opts, :depends, []),
        priority: Keyword.get(opts, :priority, 10),
        status: Keyword.get(opts, :status, :started)
      })

    record
  end

  defp compile(event), do: :ok = EventHandler.do_compile(event, :test, false)

  defp status(name), do: Event.get(:name, name).status

  defp chain(event) do
    module = ModuleStateCompiler.module_event_name(event)

    if function_exported?(module, :initialize, 0),
      do: Enum.map(module.initialize().plugins, & &1.name),
      else: []
  end
end
