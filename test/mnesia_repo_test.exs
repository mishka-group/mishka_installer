defmodule MishkaInstaller.MnesiaRepoTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.MnesiaRepo
  alias MishkaInstaller.Installer.Installer

  @events [
    [:mishka_installer, :mnesia, :init, :start],
    [:mishka_installer, :mnesia, :init, :stop],
    [:mishka_installer, :mnesia, :table],
    [:mishka_installer, :mnesia, :synchronized],
    [:mishka_installer, :mnesia, :health_check]
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

    :ok
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

  test "refuses to start when no configured cluster node is reachable" do
    tmp = Path.join(System.tmp_dir!(), "mnesia-cluster-#{System.unique_integer([:positive])}")

    Application.put_env(:mishka_installer, MnesiaRepo,
      mnesia_dir: tmp,
      essential: [Installer],
      cluster_nodes: [:"ghost@127.0.0.1"]
    )

    on_exit(fn -> File.rm_rf!(tmp) end)

    assert {:error, _} = start_supervised(MnesiaRepo)
  end
end
