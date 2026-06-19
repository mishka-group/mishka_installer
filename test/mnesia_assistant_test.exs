defmodule MishkaInstaller.MnesiaAssistantTest do
  use ExUnit.Case, async: false
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
    test "success shapes normalise to {:ok, :atomic}" do
      assert Error.error_description(:ok, :test) == {:ok, :atomic}
      assert Error.error_description({:atomic, :ok}, :test) == {:ok, :atomic}
    end

    test "already-exists becomes an error tuple" do
      assert {:error, {:aborted, {:already_exists, :some_table}}, _desc} =
               Error.error_description({:aborted, {:already_exists, :some_table}}, :test)
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
