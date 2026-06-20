defmodule MishkaInstaller.MnesiaRepoTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.MnesiaRepo
  alias MishkaInstaller.Installer.Installer

  @events [
    [:mishka_installer, :mnesia, :init, :start],
    [:mishka_installer, :mnesia, :init, :stop],
    [:mishka_installer, :mnesia, :table],
    [:mishka_installer, :mnesia, :synchronized],
    [:mishka_installer, :mnesia, :health_check],
    [:mishka_installer, :mnesia, :cluster, :nodeup],
    [:mishka_installer, :mnesia, :cluster, :nodedown]
  ]

  setup do
    System.put_env("PROJECT_PATH", File.cwd!())
    tmp = Path.join(System.tmp_dir!(), "mishka-mnesia-repo-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MishkaInstaller.MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Installer]
    )

    MishkaInstaller.subscribe("mnesia")

    test_pid = self()
    handler = {__MODULE__, make_ref()}

    :telemetry.attach_many(
      handler,
      @events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler)
      pid = Process.whereis(MnesiaRepo)
      if is_pid(pid) and Process.alive?(pid), do: GenServer.stop(MnesiaRepo)
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "boots, creates the essential tables and broadcasts :synchronized" do
    start_supervised!(MnesiaRepo)

    assert_receive %{status: :synchronized, channel: "mnesia", data: data}, 2000
    assert is_list(data.local_tables)
    assert Installer in :mnesia.system_info(:local_tables)
  end

  test "emits the init span (start + stop), a table event and synchronized" do
    start_supervised!(MnesiaRepo)

    assert_receive {:telemetry, [:mishka_installer, :mnesia, :init, :start], _meas, _meta}, 2000

    assert_receive {:telemetry, [:mishka_installer, :mnesia, :init, :stop], meas, meta}, 2000
    assert is_integer(meas.duration)
    assert meta.result == :ok

    assert_receive {:telemetry, [:mishka_installer, :mnesia, :table], _meas,
                    %{table: Installer, status: status}},
                   2000

    assert status in [:created, :already_exists, :already_loaded]

    assert_receive {:telemetry, [:mishka_installer, :mnesia, :synchronized], _meas, %{node: _}},
                   2000
  end

  test "health_check emits a telemetry health event" do
    pid = start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    send(pid, :health_check)

    assert_receive {:telemetry, [:mishka_installer, :mnesia, :health_check], meas, meta}, 2000
    assert is_integer(meas.table_count)
    assert meta.healthy? == true
    assert meta.missing == []
  end

  test "state/0 returns the repo state including essential tables" do
    start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    state = MnesiaRepo.state()
    assert state.essential == [Installer]
    assert Installer in state.tables
  end

  test "schemas/0 reports local tables with storage info" do
    start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    assert {Installer, info} = Enum.find(MnesiaRepo.schemas(), fn {t, _} -> t == Installer end)
    assert Keyword.has_key?(info, :storage_type)
  end

  test "a restart on the same dir re-announces without wiping the running DB" do
    start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    {:ok, _} = Installer.write(%{app: "keep_me", version: "1.0.0", path: "p"})
    assert Installer.get(:app, "keep_me")

    :ok = stop_supervised(MnesiaRepo)
    start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

    assert Installer.get(:app, "keep_me")
  end

  describe "dynamic membership" do
    # These configure unreachable seed/ghost peers; the repo logs the unreachable/down nodes at `:warning`.
    @describetag :capture_log
    test "a node with no configured peers stays passive (dynamic membership off)" do
      # The default / single-node case: no `cluster_nodes` => no monitoring, node events are no-ops.
      pid = start_supervised!(MnesiaRepo)
      assert_receive %{status: :synchronized, channel: "mnesia"}, 2000

      assert MnesiaRepo.state().dynamic == false

      send(pid, {:nodeup, :"x@127.0.0.1"})
      send(pid, {:nodedown, :"x@127.0.0.1"})

      refute_receive {:telemetry, [:mishka_installer, :mnesia, :cluster, _kind], _meas, _meta},
                     300

      assert Process.alive?(pid)
    end

    test "a joiner whose seed is unreachable boots :pending instead of crashing", ctx do
      Application.put_env(:mishka_installer, MnesiaRepo,
        mnesia_dir: ctx.tmp,
        essential: [Installer],
        cluster_nodes: [:"ghost@127.0.0.1"]
      )

      pid = start_supervised!(MnesiaRepo)

      assert Process.alive?(pid)
      assert MnesiaRepo.state().status == :pending
      # Configuring peers turns dynamic membership on, so the node now watches for the seed.
      assert MnesiaRepo.state().dynamic == true
      # We never created the essential table locally, so a later join can't split-brain.
      refute Installer in :mnesia.system_info(:local_tables)
      refute_receive %{status: :synchronized, channel: "mnesia"}, 300
    end

    test "{:nodeup, peer} for an unconfigured node is ignored", ctx do
      Application.put_env(:mishka_installer, MnesiaRepo,
        mnesia_dir: ctx.tmp,
        essential: [Installer],
        cluster_nodes: [:"seed@127.0.0.1"]
      )

      pid = start_supervised!(MnesiaRepo)
      assert MnesiaRepo.state().status == :pending

      send(pid, {:nodeup, :"random@127.0.0.1"})

      assert_receive {:telemetry, [:mishka_installer, :mnesia, :cluster, :nodeup], _meas,
                      %{peer: :"random@127.0.0.1", action: :ignored}}
    end

    test "{:nodeup, seed} re-attempts the join while :pending", ctx do
      Application.put_env(:mishka_installer, MnesiaRepo,
        mnesia_dir: ctx.tmp,
        essential: [Installer],
        cluster_nodes: [:"seed@127.0.0.1"]
      )

      pid = start_supervised!(MnesiaRepo)
      assert MnesiaRepo.state().status == :pending

      # The seed is still unreachable, so the retry can't complete and we stay :pending — but it
      # proves a pending node re-runs the join when a configured node connects.
      send(pid, {:nodeup, :"seed@127.0.0.1"})

      assert_receive {:telemetry, [:mishka_installer, :mnesia, :cluster, :nodeup], _meas,
                      %{peer: :"seed@127.0.0.1", action: :pending}}

      assert MnesiaRepo.state().status == :pending
    end

    test "{:nodedown, peer} only logs + emits telemetry, never evicting", ctx do
      Application.put_env(:mishka_installer, MnesiaRepo,
        mnesia_dir: ctx.tmp,
        essential: [Installer],
        cluster_nodes: [:"seed@127.0.0.1"]
      )

      pid = start_supervised!(MnesiaRepo)
      assert MnesiaRepo.state().status == :pending

      send(pid, {:nodedown, :"seed@127.0.0.1"})

      assert_receive {:telemetry, [:mishka_installer, :mnesia, :cluster, :nodedown], _meas,
                      %{peer: :"seed@127.0.0.1", db_member?: false}}

      # Nothing was evicted and the repo keeps running.
      assert Process.alive?(pid)
    end
  end
end
