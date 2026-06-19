defmodule MishkaInstaller.MnesiaAssistant.Schema do
  @moduledoc """
  Mnesia schema creation.
  """

  @doc """
  Creates the Mnesia schema on `nodes` (defaults to the current node).
  Delegates to `:mnesia.create_schema/1`.

  Returns `:ok` or `{:error, reason}` (e.g. `{:already_exists, node}`).
  """
  @spec create_schema([node()]) :: :ok | {:error, term()}
  def create_schema(nodes \\ [node()]) when is_list(nodes), do: :mnesia.create_schema(nodes)
end
