defmodule MishkaInstallerTest.Event.ModuleStateCompilerTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{ModuleStateCompiler, Event}

  setup_all do
    pid = Process.whereis(MishkaInstaller.MnesiaRepo)
    pid1 = Process.whereis(MishkaInstaller.Event.EventHandler)

    if !is_nil(pid) and Process.alive?(pid) do
      GenServer.stop(MishkaInstaller.MnesiaRepo)
    end

    if !is_nil(pid1) and Process.alive?(pid1) do
      GenServer.stop(MishkaInstaller.Event.EventHandler)
    end

    :ok
  end

  test "Create a compile time module" do
    plugin = Event.builder(%{name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps})
    :ok = ModuleStateCompiler.create([plugin], "event_c_extra")

    module = ModuleStateCompiler.module_event_name("event_c_extra")
    assert Code.ensure_loaded?(module)
    assert module.initialize?()
    %{module: _, plugins: plugins} = assert module.initialize()
    assert length(plugins) > 0
  end

  test "Purge and Create a compile time module" do
    plugin = Event.builder(%{name: MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventCOTP})
    :ok = ModuleStateCompiler.purge_create([plugin], "event_c")

    module = ModuleStateCompiler.module_event_name("event_c")
    assert Code.ensure_loaded?(module)
    assert module.initialize?()
    %{module: _, plugins: plugins} = assert module.initialize()
    assert length(plugins) > 0
  end
end
