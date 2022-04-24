defmodule MishkaInstaller do
  alias MishkaInstaller.PluginState

  @spec plugin_activity(String.t(), PluginState.t(), String.t(), String.t()) ::
          :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def plugin_activity(action, %PluginState{} = plugin, priority, status \\ "info") do
    MishkaInstaller.Activity.create_activity_by_start_child(%{
      type: "plugin",
      section: "other",
      section_id: nil,
      action: action,
      priority: priority,
      status: status,
      user_id: nil
    },
      Map.from_struct(plugin)
      |> Map.drop([:parent_pid])
    )
  end

  def ip(user_ip), do: is_bitstring(user_ip) && user_ip || Enum.join(Tuple.to_list(user_ip), ".")

  def get_config(item, section \\ :basic) do
    case Application.fetch_env(:mishka_installer, section) do
      :error -> nil
      {:ok, list} -> Keyword.fetch!(list, item)
    end
  end

  def repo() do
    case MishkaInstaller.get_config(:repo) do
      nil -> if Mix.env() != :prod, do: Ecto.Integration.TestRepo, else: ensure_compiled(nil)
      value -> value
    end
  end

  def ensure_compiled(module) do
    case Code.ensure_compiled(module) do
      {:module, _} -> module
      {:error, _} -> raise "This module does not exist or is not configured if it is related to Ecto. Please read the documentation at GitHub."
    end
  end
end
