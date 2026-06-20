defmodule MishkaInstaller.MnesiaAssistantTest do
  use ExUnit.Case, async: false
  # Some tests drive aborted Mnesia ops the Error module logs; capture those expected logs.
  @moduletag :capture_log
  alias MishkaInstaller.MnesiaAssistant
  alias MishkaInstaller.MnesiaAssistant.{Transaction, Query, Table, Error, Information}

  defmodule Rec do
    defstruct [:id, :name, :tag]
  end

  describe "tuple_to_map/4" do
    test "converts record tuples to plain maps when struct is nil" do
      assert MnesiaAssistant.tuple_to_map([{Rec, 1, "a", "x"}], [:id, :name, :tag], nil, []) ==
               [%{id: 1, name: "a", tag: "x"}]
    end

    test "drops requested keys" do
      assert MnesiaAssistant.tuple_to_map([{Rec, 1, "a", "x"}], [:id, :name, :tag], nil, [:tag]) ==
               [%{id: 1, name: "a"}]
    end

    test "wraps in a struct when given one" do
      assert MnesiaAssistant.tuple_to_map([{Rec, 1, "a", "x"}], [:id, :name, :tag], Rec, []) ==
               [%Rec{id: 1, name: "a", tag: "x"}]
    end

    test "handles :\"$end_of_table\" and {records, cont}" do
      assert MnesiaAssistant.tuple_to_map(:"$end_of_table", [:id], nil, []) == []

      assert {[%{id: 1}], :cont} =
               MnesiaAssistant.tuple_to_map({[{Rec, 1}], :cont}, [:id], nil, [])
    end
  end

  describe "match-spec helpers" do
    test "er/1 delegates to erlang_result" do
      assert MnesiaAssistant.er(:selected) == [:"$$"]
    end

    test "erl_fields/4 delegates to erlang_fields" do
      assert MnesiaAssistant.erl_fields({Rec}, [:id, :name], [:name], 1) == {Rec, :_, :"$1"}
    end
  end

  describe "Error.error_description/2" do
    import ExUnit.CaptureLog

    test "success shapes normalise to {:ok, :atomic}" do
      assert Error.error_description(:ok, :test) == {:ok, :atomic}
      assert Error.error_description({:atomic, :ok}, :test) == {:ok, :atomic}
    end

    test ":starting normalises to {:ok, :atomic} (debug log)" do
      log =
        capture_log(fn ->
          assert Error.error_description(:starting, :booting) == {:ok, :atomic}
        end)

      assert log =~ "starting"
    end

    test "already-exists becomes an error tuple (both tuple shapes)" do
      assert {:error, {:aborted, {:already_exists, :t}}, _} =
               Error.error_description({:aborted, {:already_exists, :t}}, :test)

      # the {:error, {_, {:already_exists, _}}} shape some schema ops return
      err = {:error, {:create, {:already_exists, :t}}}
      assert {:error, ^err, _} = Error.error_description(err, :test)
    end

    test "an aborted tuple reason in the known error types logs an error and describes it" do
      err = {:aborted, {:bad_type, :some_table}}

      log =
        capture_log(fn ->
          assert {:error, ^err, desc} = Error.error_description(err, :test)
          assert is_binary(desc) or is_list(desc)
        end)

      assert log =~ "error:"
    end

    test "an aborted tuple reason NOT in the known error types falls through to the catch-all" do
      err = {:aborted, {:totally_custom_reason, :x}}
      assert {:error, ^err, _desc} = Error.error_description(err, :test)
    end

    test "a bare (non-tuple) reason is described and returned" do
      err = {:aborted, :no_exists}
      assert {:error, ^err, _desc} = Error.error_description(err, :test)
    end
  end

  describe "Transaction.transaction_error/5" do
    test "builds the standard error map" do
      assert {:error, [%{field: :global, action: :reading, source: _}]} =
               Transaction.transaction_error(:no_exists, Rec, "reading", :global, :reading)
    end
  end

  describe "live Mnesia round-trip" do
    setup do
      :mnesia.stop()
      :ok = :mnesia.start()
      table = :"mnesia_assistant_test_#{System.unique_integer([:positive])}"

      {:atomic, :ok} =
        Table.create_table(table,
          attributes: [:id, :name, :tag],
          index: [:tag],
          ram_copies: [node()],
          record_name: table
        )

      :ok = Table.wait_for_tables([table], 5000)
      on_exit(fn -> :mnesia.delete_table(table) end)
      {:ok, table: table}
    end

    test "write / read / index_read / match / select / all_keys / delete / clear", %{table: table} do
      assert {:atomic, :ok} =
               Transaction.transaction(fn ->
                 Query.write({table, 1, "alice", "x"})
                 Query.write({table, 2, "bob", "y"})
               end)

      assert {:atomic, [{^table, 1, "alice", "x"}]} =
               Transaction.transaction(fn -> Query.read(table, 1) end)

      assert {:atomic, [{^table, 2, "bob", "y"}]} =
               Transaction.transaction(fn -> Query.index_read(table, "y", :tag) end)

      assert {:atomic, matched} =
               Transaction.transaction(fn -> Query.match_object({table, :_, :_, :_}) end)

      assert length(matched) == 2

      assert {:atomic, ids} =
               Transaction.transaction(fn ->
                 Query.select(table, [{{table, :"$1", :_, :_}, [], [:"$1"]}])
               end)

      assert Enum.sort(ids) == [1, 2]

      assert Enum.sort(Transaction.ets(fn -> Table.all_keys(table) end)) == [1, 2]

      assert {:atomic, :ok} = Transaction.transaction(fn -> Query.delete(table, 1, :write) end)
      assert {:atomic, []} = Transaction.transaction(fn -> Query.read(table, 1) end)

      assert {:atomic, :ok} = Table.clear_table(table)
      assert Transaction.ets(fn -> Table.all_keys(table) end) == []
    end

    test "Information.system_info lists the local table", %{table: table} do
      assert table in Information.system_info(:local_tables)
    end

    test "add_table_copy / change_table_copy_type / clear_table error paths", %{table: table} do
      # copying to a node that already holds the table aborts with already_exists
      assert {:aborted, {:already_exists, ^table, _node}} =
               Table.add_table_copy(table, node(), :ram_copies)

      # operations on a non-existent table abort
      assert {:aborted, _} = Table.change_table_copy_type(:ghost_table, node(), :ram_copies)
      assert {:aborted, _} = Table.clear_table(:ghost_table)
    end

    test "wait_for_tables/2 times out for a table that never loads" do
      ghost = :"ghost_#{System.unique_integer([:positive])}"
      result = Table.wait_for_tables([ghost], 50)
      assert match?({:timeout, [^ghost]}, result) or match?({:error, _}, result)
    end
  end

  # Proves the PRODUCTION storage path: a `disc_copies` table backed by an on-disk schema keeps its
  # data across a real Mnesia stop/start (a reboot). The rest of the suite uses `ram_copies`, so this
  # is the only test that exercises disc persistence.
  describe "disc_copies persistence" do
    setup do
      prev_dir = :mnesia.system_info(:directory)
      tmp = Path.join(System.tmp_dir!(), "mnesia-disc-#{System.unique_integer([:positive])}")
      :mnesia.stop()
      Application.put_env(:mnesia, :dir, String.to_charlist(tmp))
      File.mkdir_p!(tmp)
      :ok = :mnesia.create_schema([node()])
      :ok = :mnesia.start()

      on_exit(fn ->
        :mnesia.stop()
        File.rm_rf!(tmp)
        Application.put_env(:mnesia, :dir, prev_dir)
      end)

      :ok
    end

    test "a disc_copies record survives a mnesia stop/start" do
      table = :"disc_persist_#{System.unique_integer([:positive])}"

      {:atomic, :ok} =
        Table.create_table(table,
          attributes: [:id, :name],
          disc_copies: [node()],
          record_name: table
        )

      :ok = Table.wait_for_tables([table], 5000)
      {:atomic, :ok} = Transaction.transaction(fn -> Query.write({table, 1, "persisted"}) end)

      # simulate a reboot — stop and restart Mnesia with the same on-disk dir
      :stopped = :mnesia.stop()
      :ok = :mnesia.start()
      :ok = Table.wait_for_tables([table], 5000)

      assert {:atomic, [{^table, 1, "persisted"}]} =
               Transaction.transaction(fn -> Query.read(table, 1) end)
    end
  end
end
