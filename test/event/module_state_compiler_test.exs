defmodule MishkaInstallerTest.Event.ModuleStateCompilerTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.Event.{Event, Hook, ModuleStateCompiler}

  setup_all do
    pid = Process.whereis(MishkaInstaller.MnesiaRepo)
    pid1 = Process.whereis(MishkaInstaller.Event.EventHandler)

    if !is_nil(pid) and Process.alive?(pid) do
      MishkaInstallerTest.Support.ProcessHelpers.stop_if_running(MishkaInstaller.MnesiaRepo)
    end

    if !is_nil(pid1) and Process.alive?(pid1) do
      MishkaInstallerTest.Support.ProcessHelpers.stop_if_running(
        MishkaInstaller.Event.EventHandler
      )
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
    assert [_ | _] = plugins
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
    assert [_ | _] = plugins
  end

  test "create/3 with inaccessible plugins compiles a stub that runs none of them" do
    {:ok, plugin} =
      Event.builder(%{
        name: MishkaTmp.NotLoaded,
        event: "ms_err_evt",
        extension: :mishka_installer
      })

    :ok = ModuleStateCompiler.create([plugin], "ms_err_evt", [MishkaTmp.NotLoaded])

    module = ModuleStateCompiler.module_event_name("ms_err_evt")
    assert module.mode() == :error
    assert module.call(%{a: 1}) == %{a: 1}
    assert module.call(%{a: 1}, cannot_run: :refused) == :refused
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

  describe "finish_call/3 ===>" do
    test "return hands back the state the call was given" do
      assert ModuleStateCompiler.finish_call({:ok, %{a: 2}}, %{a: 1}, return: true) == %{a: 1}
      assert ModuleStateCompiler.finish_call(:anything, :given, return: false) == :given
    end

    test "private is merged into a keyword list or a map, and into nothing else" do
      private = [private: [p: 1]]
      map_private = [private: %{p: 1}]

      assert ModuleStateCompiler.finish_call([a: 1], :s, private) == [a: 1, p: 1]
      assert ModuleStateCompiler.finish_call({:ok, [a: 1]}, :s, private) == {:ok, [a: 1, p: 1]}
      assert ModuleStateCompiler.finish_call(%{a: 1}, :s, map_private) == %{a: 1, p: 1}

      assert ModuleStateCompiler.finish_call({:ok, %{a: 1}}, :s, map_private) ==
               {:ok, %{a: 1, p: 1}}

      assert ModuleStateCompiler.finish_call([1, 2], :s, private) == [1, 2]
      assert ModuleStateCompiler.finish_call({:ok, [1, 2]}, :s, private) == {:ok, [1, 2]}
      assert ModuleStateCompiler.finish_call("binary", :s, private) == "binary"
      assert ModuleStateCompiler.finish_call({:ok, "binary"}, :s, private) == {:ok, "binary"}

      assert ModuleStateCompiler.finish_call({:noreply, :socket}, :s, private) ==
               {:noreply, :socket}

      assert ModuleStateCompiler.finish_call({:error, [:e]}, :s, private) == {:error, [:e]}
    end

    test "without private every shape comes back as the plugins left it" do
      for performed <- [[a: 1], {:ok, [a: 1]}, %{a: 1}, {:ok, %{a: 1}}, {:error, [:e]}, :other] do
        assert ModuleStateCompiler.finish_call(performed, :s, []) == performed
      end
    end
  end

  describe "create/3 when the module cannot be built ===>" do
    @describetag :capture_log

    test "a plugin that cannot be compiled into a module is an error tuple, not a raise" do
      event = "ms_unbuildable_#{System.unique_integer([:positive])}"

      {:ok, plugin} =
        Event.builder(%{
          name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
          event: event,
          extension: :mishka_installer,
          extra: [%{callback: fn -> :not_a_literal end}]
        })

      assert {:error, [%{field: :event, action: :compile, message: message}]} =
               ModuleStateCompiler.create([plugin], event)

      assert message == "The module of the event could not be compiled."

      assert {:error, [%{action: :compile}]} = ModuleStateCompiler.purge_create([plugin], event)
      refute ModuleStateCompiler.compile_initialize?(event)
      assert Hook.call(event, %{a: 1}) == %{a: 1}
    end

    test "a module that was built before keeps answering after a failed rebuild" do
      event = "ms_rebuild_#{System.unique_integer([:positive])}"

      {:ok, good} =
        Event.builder(%{
          name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
          event: event,
          extension: :mishka_installer
        })

      {:ok, bad} =
        Event.builder(%{
          name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
          event: event,
          extension: :mishka_installer,
          extra: [%{callback: fn -> :not_a_literal end}]
        })

      :ok = ModuleStateCompiler.create([good], event)
      module = ModuleStateCompiler.event_module(event)
      assert module.initialize().plugins == [good]

      assert {:error, [%{action: :compile}]} = ModuleStateCompiler.create([bad], event)
      assert module.initialize().plugins == [good]
    end
  end

  describe "an event that was never compiled ===>" do
    test "every read path answers without creating an atom or a cache key" do
      event = "never_compiled_#{System.unique_integer([:positive])}"
      module_name = "MishkaInstaller.Event.ModuleStateCompiler.State." <> Macro.camelize(event)

      assert Hook.call(event, %{a: 1}) == %{a: 1}
      assert Hook.call(event, %{a: 1}, cannot_run: :refused) == %{a: 1}
      assert_raise UndefinedFunctionError, fn -> Hook.call!(event, %{a: 1}) end
      assert Hook.profile(event, %{a: 1}) == {:error, :not_compiled}
      assert %{compiled?: false, mode: :unknown, plugins: []} = Hook.event_health(event)

      assert ModuleStateCompiler.event_module(event) == nil
      refute ModuleStateCompiler.compile_initialize?(event)
      refute ModuleStateCompiler.safe_initialize?(event)
      refute ModuleStateCompiler.rescue_initialize?(event)
      :ok = ModuleStateCompiler.purge(event)
      :ok = ModuleStateCompiler.purge([event])

      assert :persistent_term.get({ModuleStateCompiler, :name_cache, event}, :none) == :none

      for name <- [module_name, "Elixir." <> module_name] do
        assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
      end
    end

    test "an event that was created is found by the lookup, and is gone from it after purge" do
      event = "found_evt_#{System.unique_integer([:positive])}"

      {:ok, plugin} =
        Event.builder(%{
          name: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps,
          event: event,
          extension: :mishka_installer
        })

      :ok = ModuleStateCompiler.create([plugin], event)

      module = ModuleStateCompiler.event_module(event)
      assert module == ModuleStateCompiler.module_event_name(event)
      assert module.initialize?()
      assert %{compiled?: true, mode: :ok} = Hook.event_health(event)

      assert {:ok, [%{plugin: MishkaInstallerTest.Support.MishkaPlugin.EventCDeps}]} =
               Hook.profile(event, %{})

      :ok = ModuleStateCompiler.purge(event)
      refute ModuleStateCompiler.compile_initialize?(event)
      assert Hook.call(event, %{a: 1}) == %{a: 1}
      assert_raise UndefinedFunctionError, fn -> Hook.call!(event, %{a: 1}) end
    end
  end
end
