defmodule MishkaInstaller.MnesiaAssistant.Information do
  @moduledoc """
  Read-only introspection of the running Mnesia system.
  """

  @doc """
  Returns runtime information for `type` (e.g. `:db_nodes`, `:extra_db_nodes`, `:local_tables`,
  `:tables`, `:directory`). Delegates to `:mnesia.system_info/1`.
  """
  @spec system_info(atom()) :: term()
  def system_info(type) when is_atom(type), do: :mnesia.system_info(type)
end
