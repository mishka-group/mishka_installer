defmodule MishkaInstaller.MnesiaAssistant.Error do
  @moduledoc """
  Turns raw Mnesia results into a normalised `{:ok, :atomic}` / `{:error, error, description}` shape
  and logs them.

  Mnesia transactions and schema operations return `{:atomic, value}` or `{:aborted, reason}`, and
  `reason` is often an atom from the documented
  [error list](https://www.erlang.org/doc/man/mnesia#data-types). `error_description/2` maps those to
  a human-readable description and the appropriate log level.
  """
  require Logger

  @error_types [
    :nested_transaction,
    :badarg,
    :no_transaction,
    :combine_error,
    :bad_index,
    :already_exists,
    :index_exists,
    :no_exists,
    :system_limit,
    :mnesia_down,
    :not_a_db_node,
    :bad_type,
    :node_not_running,
    :truncated_binary_file,
    :active,
    :illegal
  ]

  @doc """
  Returns a descriptive term for a Mnesia error. Delegates to `:mnesia.error_description/1`.
  """
  @spec error_description(term()) :: term()
  def error_description(error), do: :mnesia.error_description(error)

  @doc """
  Normalises and logs a Mnesia result for the given `identifier`.

  Returns `{:ok, :atomic}` on success, or `{:error, error, description}` otherwise. Successful and
  "already exists" outcomes are logged at a low level; genuine failures are logged as errors.
  """
  @spec error_description(term(), term()) :: {:ok, :atomic} | {:error, term(), term()}
  def error_description(error, identifier) when error in [{:atomic, :ok}, :ok] do
    Logger.debug("Identifier: #{inspect(identifier)} ::: Mnesia action completed successfully.")
    {:ok, :atomic}
  end

  def error_description(:starting, identifier) do
    Logger.debug("Identifier: #{inspect(identifier)} ::: Mnesia action is starting.")
    {:ok, :atomic}
  end

  def error_description({:aborted, {:already_exists, _}} = error, identifier) do
    already_exists(error, identifier)
  end

  def error_description({:error, {_, {:already_exists, _}}} = error, identifier) do
    already_exists(error, identifier)
  end

  def error_description({:aborted, reason} = error, identifier) when is_tuple(reason) do
    if elem(reason, 0) in @error_types do
      converted = error_description(error)

      Logger.error(
        "Identifier: #{inspect(identifier)} ::: MnesiaError: #{inspect(error)} ::: #{inspect(converted)}"
      )

      {:error, error, describe(converted)}
    else
      error_description(error, identifier)
    end
  end

  def error_description(error, identifier) do
    converted = error_description(error)

    Logger.error(
      "Identifier: #{inspect(identifier)} ::: MnesiaError: #{inspect(error)} ::: #{inspect(converted)}"
    )

    {:error, error, converted}
  end

  defp already_exists(error, identifier) do
    converted = error_description(error)

    Logger.debug(
      "Identifier: #{inspect(identifier)} ::: Mnesia resource already exists ::: #{inspect(converted)}"
    )

    {:error, error, describe(converted)}
  end

  defp describe(converted) when is_tuple(converted), do: to_string(elem(converted, 0))
  defp describe(converted), do: converted
end
