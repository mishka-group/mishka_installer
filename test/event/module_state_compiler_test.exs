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
    {:ok, plugin} =
      Event.builder(%{
        name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
        event: "event_c_extra",
        extension: :mishka_installer
      })

    :ok = ModuleStateCompiler.create([plugin], "event_c_extra")

    module = ModuleStateCompiler.module_event_name("event_c_extra")
    assert Code.ensure_loaded?(module)
    assert module.initialize?()
    %{module: _, plugins: plugins} = assert module.initialize()
    assert length(plugins) > 0
  end

  test "Purge and Create a compile time module" do
    {:ok, plugin} =
      Event.builder(%{
        name: MishkaInstallerTest.Support.MishkaPlugin.Bulk.EventCOTP,
        event: "event_c",
        extension: :mishka_installer
      })

    :ok = ModuleStateCompiler.purge_create([plugin], "event_c")

    module = ModuleStateCompiler.module_event_name("event_c")
    assert Code.ensure_loaded?(module)
    assert module.initialize?()
    %{module: _, plugins: plugins} = assert module.initialize()
    assert length(plugins) > 0
  end

  test "create/3 with inaccessible plugins compiles an error stub" do
    {:ok, plugin} =
      Event.builder(%{
        name: MishkaTmp.NotLoaded,
        event: "ms_err_evt",
        extension: :mishka_installer
      })

    :ok = ModuleStateCompiler.create([plugin], "ms_err_evt", [MishkaTmp.NotLoaded])

    module = ModuleStateCompiler.module_event_name("ms_err_evt")
    assert module.mode() == :error
    assert {:error, [%{action: :call, plugins: [MishkaTmp.NotLoaded]}]} = module.call(%{})
  end

  test "initialize? / safe_initialize? / compile_initialize? / rescue_initialize? track compile state" do
    evt = "ms_init_evt"
    # uncompiled: the safe/compile/rescue variants say false (and don't raise)
    refute ModuleStateCompiler.safe_initialize?(evt)
    refute ModuleStateCompiler.compile_initialize?(evt)
    refute ModuleStateCompiler.rescue_initialize?(evt)

    {:ok, plugin} =
      Event.builder(%{
        name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
        event: evt,
        extension: :mishka_installer
      })

    :ok = ModuleStateCompiler.create([plugin], evt)

    assert ModuleStateCompiler.initialize?(evt)
    assert ModuleStateCompiler.safe_initialize?(evt)
    assert ModuleStateCompiler.compile_initialize?(evt)
    assert ModuleStateCompiler.rescue_initialize?(evt)
  end

  test "purge/1 removes a compiled module (single and list forms)" do
    {:ok, plugin} =
      Event.builder(%{
        name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
        event: "ms_purge_evt",
        extension: :mishka_installer
      })

    :ok = ModuleStateCompiler.create([plugin], "ms_purge_evt")
    assert ModuleStateCompiler.compile_initialize?("ms_purge_evt")

    :ok = ModuleStateCompiler.purge("ms_purge_evt")
    refute ModuleStateCompiler.compile_initialize?("ms_purge_evt")

    :ok = ModuleStateCompiler.create([plugin], "ms_purge_evt")
    :ok = ModuleStateCompiler.purge(["ms_purge_evt"])
    refute ModuleStateCompiler.compile_initialize?("ms_purge_evt")
  end
end
