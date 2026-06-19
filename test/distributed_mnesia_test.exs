defmodule MishkaInstaller.DistributedMnesiaTest do
  use ExUnit.Case, async: false
  alias MishkaInstaller.MnesiaRepo
  alias MishkaInstaller.MnesiaAssistant
  alias MishkaInstaller.MnesiaAssistant.{Query, Table, Transaction}

  @moduletag :distributed

  setup do
    ensure_distributed()
    cookie = "#{:erlang.get_cookie()}"
    paths = Enum.flat_map(:code.get_path(), fn p -> [~c"-pa", ~c"#{p}"] end)

    {:ok, _peer, b} =
      :peer.start_link(%{
        name: :"worker_#{System.unique_integer([:positive])}",
        host: ~c"127.0.0.1",
        args: [~c"-setcookie", ~c"#{cookie}"] ++ paths
      })

    wait_connected(b)

    tmp_a = tmp_dir()
    tmp_b = tmp_dir()
    File.mkdir_p!(tmp_a)
    File.mkdir_p!(tmp_b)

    # `:peer.start_link` tears the peer node down via the link when this test process exits, so we
    # only clean up the local Mnesia, the tmp dirs, and any `MnesiaCore.*` dump written to the CWD.
    on_exit(fn ->
      :mnesia.stop()
      File.rm_rf!(tmp_a)
      File.rm_rf!(tmp_b)
      Enum.each(Path.wildcard("MnesiaCore.*"), &File.rm/1)
    end)

    {:ok, b: b, tmp_a: tmp_a, tmp_b: tmp_b}
  end

  test "a table on node A replicates to a node B that joins the cluster", ctx do
    a = node()

    # Node A — the standalone path: stop (Mnesia is auto-started via extra_applications), point at a
    # fresh dir, create the disc schema, start, write a record.
    :mnesia.stop()
    :application.set_env(:mnesia, :dir, String.to_charlist(ctx.tmp_a))
    :mnesia.create_schema([a])
    MnesiaAssistant.start()

    {:atomic, :ok} =
      Table.create_table(:cluster_demo,
        attributes: [:id, :name],
        disc_copies: [a],
        record_name: :cluster_demo
      )

    :ok = Table.wait_for_tables([:cluster_demo], 5000)
    {:atomic, :ok} = Transaction.transaction(fn -> Query.write({:cluster_demo, 1, "from_A"}) end)

    # Node B — the join path: connect, make the schema local+disc, copy the table.
    :erpc.call(ctx.b, :application, :set_env, [:mnesia, :dir, String.to_charlist(ctx.tmp_b)])
    :erpc.call(ctx.b, :mnesia, :start, [])
    {:ok, [^a]} = :erpc.call(ctx.b, :mnesia, :change_config, [:extra_db_nodes, [a]])
    :erpc.call(ctx.b, :mnesia, :change_table_copy_type, [:schema, ctx.b, :disc_copies])

    {:atomic, :ok} =
      :erpc.call(ctx.b, :mnesia, :add_table_copy, [:cluster_demo, ctx.b, :disc_copies])

    :ok = :erpc.call(ctx.b, :mnesia, :wait_for_tables, [[:cluster_demo], 5000])

    # B reads the record written on A — replication works across the two nodes.
    assert :erpc.call(ctx.b, :mnesia, :dirty_read, [{:cluster_demo, 1}]) ==
             [{:cluster_demo, 1, "from_A"}]
  end

  test "a :pending joiner joins via {:nodeup, _} when its seed connects, then sees its data",
       ctx do
    # A (this node) is configured as a joiner pointed at B, but B's Mnesia is not up yet, so A boots
    # :pending instead of crashing.
    Application.put_env(:mishka_installer, MnesiaRepo,
      mnesia_dir: ctx.tmp_a,
      essential: [:cluster_demo],
      cluster_nodes: [ctx.b],
      dynamic_membership: true
    )

    {:ok, _pid} = MnesiaRepo.start_link()

    on_exit(fn ->
      pid = Process.whereis(MnesiaRepo)
      if is_pid(pid) and Process.alive?(pid), do: GenServer.stop(MnesiaRepo)
      Application.delete_env(:mishka_installer, MnesiaRepo)
    end)

    assert MnesiaRepo.state().status == :pending
    refute :cluster_demo in :mnesia.system_info(:local_tables)

    # Bring up seed B with the table and a record.
    :erpc.call(ctx.b, :mnesia, :stop, [])
    :erpc.call(ctx.b, :application, :set_env, [:mnesia, :dir, String.to_charlist(ctx.tmp_b)])
    :ok = :erpc.call(ctx.b, :mnesia, :create_schema, [[ctx.b]])
    :ok = :erpc.call(ctx.b, :mnesia, :start, [])

    {:atomic, :ok} =
      :erpc.call(ctx.b, :mnesia, :create_table, [
        :cluster_demo,
        [attributes: [:id, :name], disc_copies: [ctx.b], record_name: :cluster_demo]
      ])

    :ok = :erpc.call(ctx.b, :mnesia, :wait_for_tables, [[:cluster_demo], 5000])
    :ok = :erpc.call(ctx.b, :mnesia, :dirty_write, [{:cluster_demo, 1, "from_B"}])

    # B is connected at the BEAM level but its nodeup fired before MnesiaRepo started; replay it.
    send(Process.whereis(MnesiaRepo), {:nodeup, ctx.b})

    # The :state call is processed after the (synchronous) join, so by now A is a member.
    assert MnesiaRepo.state().status == :synchronized
    assert :cluster_demo in :mnesia.system_info(:local_tables)
    assert :mnesia.dirty_read({:cluster_demo, 1}) == [{:cluster_demo, 1, "from_B"}]
  end

  defp wait_connected(node, tries \\ 100)
  defp wait_connected(_node, 0), do: raise("peer node never connected")

  defp wait_connected(node, tries) do
    if node in Node.list() and Node.ping(node) == :pong do
      :ok
    else
      Process.sleep(20)
      wait_connected(node, tries - 1)
    end
  end

  defp tmp_dir(), do: Path.join(System.tmp_dir!(), "mn-#{System.unique_integer([:positive])}")

  defp ensure_distributed() do
    if path = System.find_executable("epmd"), do: System.cmd(path, ["-daemon"])

    case :net_kernel.start([:"primary@127.0.0.1", :longnames]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
