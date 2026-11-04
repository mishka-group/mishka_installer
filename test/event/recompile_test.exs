# `Blocker` holds a caller inside the chain until the test releases it, so the event can be rebuilt
# while that caller still runs the version it entered. `Two` and `Three` mark which version ran.
defmodule MishkaInstallerTest.Event.RecompileTest.Blocker do
  @moduledoc false
  def call(%{block: test} = state) do
    send(test, {:inside, self()})

    receive do
      :release -> {:reply, Map.put(state, :blocked, true)}
    end
  end

  def call(state), do: {:reply, state}
end

defmodule MishkaInstallerTest.Event.RecompileTest.Two do
  @moduledoc false
  def call(state), do: {:reply, Map.put(state, :two, true)}
end

defmodule MishkaInstallerTest.Event.RecompileTest.Three do
  @moduledoc false
  def call(state), do: {:reply, Map.put(state, :three, true)}
end

defmodule MishkaInstallerTest.Event.RecompileTest do
  use ExUnit.Case, async: false

  alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}
  alias MishkaInstallerTest.Event.RecompileTest.{Blocker, Three, Two}

  @event "recompile_running_evt"

  setup do
    on_exit(fn -> ModuleStateCompiler.purge(@event) end)
    compile([Blocker])
  end

  defp compile(plugins) do
    built =
      for name <- plugins do
        {:ok, plugin} = Event.builder(%{name: name, event: @event, extension: :mishka_installer})
        plugin
      end

    :ok = ModuleStateCompiler.purge_create(built, @event)
  end

  # A caller that runs the event and stops inside `Blocker` until it gets `:release`.
  defp blocked_caller do
    test = self()

    {caller, ref} =
      spawn_monitor(fn -> send(test, {:answer, Hook.call(@event, %{block: test})}) end)

    assert_receive {:inside, ^caller}
    {caller, ref}
  end

  defp finishes(caller, ref) do
    test = self()
    send(caller, :release)
    assert_receive {:answer, %{block: ^test, blocked: true}}
    assert_receive {:DOWN, ^ref, :process, ^caller, :normal}
  end

  test "a caller inside a plugin finishes normally while its event is rebuilt twice" do
    {caller, ref} = blocked_caller()

    compile([Blocker, Two])
    compile([Blocker, Three])
    assert Hook.call(@event, %{}) == %{three: true}

    finishes(caller, ref)
  end

  test "a caller inside a plugin finishes normally while its event is rebuilt many times" do
    {caller, ref} = blocked_caller()

    for plugins <- [[Blocker, Two], [Blocker, Three], [Two], [Three], [Blocker, Two, Three]] do
      compile(plugins)
    end

    assert Hook.call(@event, %{}) == %{two: true, three: true}
    finishes(caller, ref)
  end

  test "a caller inside a plugin finishes normally when its rebuilt event is purged" do
    {caller, ref} = blocked_caller()

    compile([Blocker, Two])
    :ok = ModuleStateCompiler.purge(@event)
    assert ModuleStateCompiler.event_module(@event) == nil
    assert Hook.call(@event, %{}) == %{}

    finishes(caller, ref)
  end

  test "a slot no caller runs any more is dropped by the next rebuilds" do
    {caller, ref} = blocked_caller()
    compile([Blocker, Two])
    compile([Blocker, Three])
    slot = ModuleStateCompiler.event_module(@event)
    refute slot == ModuleStateCompiler.module_event_name(@event)
    finishes(caller, ref)

    compile([Two])
    compile([Three])

    refute :erlang.module_loaded(slot)
    refute :erlang.check_old_code(slot)
    assert Hook.call(@event, %{}) == %{three: true}
  end

  test "slots stay bounded while callers keep outliving rebuilds" do
    callers =
      for plugins <- [[Blocker, Two], [Blocker, Three], [Blocker, Two, Three]] do
        caller = blocked_caller()
        compile(plugins)
        caller
      end

    for {caller, ref} <- callers, do: finishes(caller, ref)
    for plugins <- [[Two], [Three], [Two, Three]], do: compile(plugins)

    assert loaded_slots() == [ModuleStateCompiler.event_module(@event)]
  end

  test "purge/1 leaves no module or key of the event behind once nothing runs it" do
    {caller, ref} = blocked_caller()
    compile([Blocker, Two])
    compile([Blocker, Three])
    finishes(caller, ref)
    slots = loaded_slots()

    :ok = ModuleStateCompiler.purge(@event)

    for module <- slots do
      refute :erlang.module_loaded(module)
      refute :erlang.check_old_code(module)
    end

    for key <- [:compiled, :name_cache, :last_slot] do
      assert :persistent_term.get({ModuleStateCompiler, key, @event}, :none) == :none
    end
  end

  # Every module of this event that is loaded or has an old version, in slot order.
  defp loaded_slots do
    name = Atom.to_string(ModuleStateCompiler.module_event_name(@event))

    suffix =
      String.replace_prefix(name, "Elixir.MishkaInstaller.Event.ModuleStateCompiler.State.", "")

    for {module, _} <- :code.all_loaded(),
        text = Atom.to_string(module),
        text == name or
          (String.starts_with?(text, "Elixir.MishkaInstaller.Event.ModuleStateCompiler.State") and
             String.ends_with?(text, "." <> suffix)),
        do: module
  end

  test "once no caller runs an old version, the event is built under its own name again" do
    {caller, ref} = blocked_caller()
    compile([Blocker, Two])
    compile([Blocker, Three])
    finishes(caller, ref)

    compile([Two])
    compile([Three])

    assert ModuleStateCompiler.event_module(@event) ==
             ModuleStateCompiler.module_event_name(@event)

    assert Hook.call(@event, %{}) == %{three: true}
  end
end
