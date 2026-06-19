defmodule MishkaInstaller.MnesiaAssistant.Table do
  @moduledoc """
  Table lifecycle helpers (create / wait / clear / keys).
  """

  @doc """
  Creates `table` from a keyword list of options (`:attributes`, `:index`, `:disc_copies`, ...).
  Delegates to `:mnesia.create_table/2`.

  Returns `{:atomic, :ok}` or `{:aborted, reason}`.
  """
  @spec create_table(atom(), keyword()) :: {:atomic, :ok} | {:aborted, term()}
  def create_table(table, opts) when is_list(opts), do: :mnesia.create_table(table, opts)

  @doc """
  Blocks until `tables` are loaded, up to `timeout` (ms or `:infinity`).
  Delegates to `:mnesia.wait_for_tables/2`.
  """
  @spec wait_for_tables([atom()], timeout()) :: :ok | {:timeout, [atom()]} | {:error, term()}
  def wait_for_tables(tables, timeout) when is_list(tables) do
    :mnesia.wait_for_tables(tables, timeout)
  end

  @doc """
  Removes all records from `table`. Delegates to `:mnesia.clear_table/1`.
  """
  @spec clear_table(atom()) :: {:atomic, :ok} | {:aborted, term()}
  def clear_table(table), do: :mnesia.clear_table(table)

  @doc """
  Returns every key in `table`. Delegates to `:mnesia.all_keys/1` and must run inside an activity.
  """
  @spec all_keys(atom()) :: [term()]
  def all_keys(table), do: :mnesia.all_keys(table)

  @doc """
  Replicates `table` (or `:schema`) to `node` with the given storage type. Delegates to
  `:mnesia.add_table_copy/3`. Returns `{:atomic, :ok}` or `{:aborted, reason}`.
  """
  @spec add_table_copy(atom(), node(), :ram_copies | :disc_copies | :disc_only_copies) ::
          {:atomic, :ok} | {:aborted, term()}
  def add_table_copy(table, node, type), do: :mnesia.add_table_copy(table, node, type)

  @doc """
  Changes the storage type of `table` (or `:schema`) on `node`. Delegates to
  `:mnesia.change_table_copy_type/3`. Returns `{:atomic, :ok}` or `{:aborted, reason}`.
  """
  @spec change_table_copy_type(atom(), node(), :ram_copies | :disc_copies | :disc_only_copies) ::
          {:atomic, :ok} | {:aborted, term()}
  def change_table_copy_type(table, node, type),
    do: :mnesia.change_table_copy_type(table, node, type)
end
