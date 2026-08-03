defmodule MishkaInstaller.Helper.MnesiaAssistant.Transaction do
  @moduledoc """
  Runs Mnesia activities and maps aborted results to the installer's error shape.
  """
  alias MishkaInstaller.Helper.MnesiaAssistant.Error

  @doc """
  Runs `fun` inside a Mnesia transaction. Delegates to `:mnesia.transaction/1`.

  Returns `{:atomic, result}` or `{:aborted, reason}`.
  """
  @spec transaction((-> any())) :: {:atomic, any()} | {:aborted, term()}
  def transaction(fun) when is_function(fun), do: :mnesia.transaction(fun)

  @doc """
  Runs `fun` inside a **durable** transaction: `:mnesia.sync_transaction/1` to commit on every node
  holding a copy of the table, then `:mnesia.sync_log/0` to flush the transaction log to disk before
  returning.

  Use it for writes that must survive an unclean node exit. `transaction/1` alone buffers the commit
  and only reaches the disk on the periodic dump (`dump_log_time_threshold`, three minutes by
  default), so a node that dies in between comes back with the old record — and a plugin's
  `:stopped`/`:started` status is an operator's setting, not a cache.

  Returns `{:atomic, result}` or `{:aborted, reason}`.
  """
  @spec durable_transaction((-> any())) :: {:atomic, any()} | {:aborted, term()}
  def durable_transaction(fun) when is_function(fun) do
    case :mnesia.sync_transaction(fun) do
      {:atomic, _result} = committed ->
        :mnesia.sync_log()
        committed

      aborted ->
        aborted
    end
  end

  @doc """
  Runs `fun` as a fast, dirty `ets` activity. Delegates to `:mnesia.ets/1`.

  > Only safe for `ram_copies` tables or read-only access on `disc_copies`.
  """
  @spec ets((-> any())) :: any()
  def ets(fun) when is_function(fun), do: :mnesia.ets(fun)

  @doc """
  Builds a standard `{:error, [map]}` from an aborted transaction `reason`.

  The returned map carries `:message`, `:field`, `:action` and the raw `:source` error, so callers
  can surface a consistent error across the codebase.

  ## Example

  ```elixir
  transaction_error(reason, MyTable, "reading", :global, :database)
  ```
  """
  @spec transaction_error(term(), module(), String.t(), atom(), atom()) ::
          {:error, [map()]}
  def transaction_error(reason, module, type, field, action) do
    {:error, error, msg} = Error.error_description({:aborted, reason}, module)

    message = "Unfortunately, there is a problem in #{type} data in the database. #{inspect(msg)}"

    {:error, [%{message: message, field: field, action: action, source: error}]}
  end
end
