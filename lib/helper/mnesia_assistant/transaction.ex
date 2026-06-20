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
