defmodule MishkaInstaller.Helper.MnesiaAssistant.Query do
  @moduledoc """
  Record-level Mnesia operations (read / write / delete / select / match).

  Every function must run inside a `MishkaInstaller.Helper.MnesiaAssistant.Transaction` activity;
  the `dirty_*` reads run in `MishkaInstaller.Helper.MnesiaAssistant.Transaction.dirty/1`.
  """

  @doc """
  Reads the records stored under `key` in `table`. Delegates to `:mnesia.read/2`.
  """
  @spec read(atom(), term()) :: [tuple()]
  def read(table, key), do: :mnesia.read(table, key)

  @doc """
  Reads records via a secondary index `attr` matching `key`. Delegates to `:mnesia.index_read/3`.
  """
  @spec index_read(atom(), term(), atom()) :: [tuple()]
  def index_read(table, key, attr), do: :mnesia.index_read(table, key, attr)

  @doc """
  Writes a full record tuple (`{Table, field1, field2, ...}`). Delegates to `:mnesia.write/1`.
  """
  @spec write(tuple()) :: :ok
  def write(record), do: :mnesia.write(record)

  @doc """
  Deletes the record at `key` in `table` with the given lock. Delegates to `:mnesia.delete/3`.
  """
  @spec delete(atom(), term(), :write | :sticky_write) :: :ok
  def delete(table, key, lock_type) when lock_type in [:write, :sticky_write] do
    :mnesia.delete(table, key, lock_type)
  end

  @doc """
  Runs a match specification against `table`. Delegates to `:mnesia.select/2`.
  """
  @spec select(atom(), list()) :: list()
  def select(table, spec), do: :mnesia.select(table, spec)

  @doc """
  Returns every record in a table matching `pattern`. Delegates to `:mnesia.match_object/1`.
  """
  @spec match_object(tuple()) :: [tuple()]
  def match_object(pattern), do: :mnesia.match_object(pattern)

  @doc """
  Reads the records stored under `key` in `table` without a lock. Delegates to
  `:mnesia.dirty_read/2`.
  """
  @spec dirty_read(atom(), term()) :: [tuple()]
  def dirty_read(table, key), do: :mnesia.dirty_read(table, key)

  @doc """
  Reads the records whose indexed `attr` is `key` without a lock. Delegates to
  `:mnesia.dirty_index_read/3`.
  """
  @spec dirty_index_read(atom(), term(), atom()) :: [tuple()]
  def dirty_index_read(table, key, attr), do: :mnesia.dirty_index_read(table, key, attr)

  @doc """
  Runs a match specification against `table` without a lock. Delegates to
  `:mnesia.dirty_select/2`.
  """
  @spec dirty_select(atom(), list()) :: list()
  def dirty_select(table, spec), do: :mnesia.dirty_select(table, spec)

  @doc """
  Returns every record in a table matching `pattern` without a lock. Delegates to
  `:mnesia.dirty_match_object/1`.
  """
  @spec dirty_match_object(tuple()) :: [tuple()]
  def dirty_match_object(pattern), do: :mnesia.dirty_match_object(pattern)
end
