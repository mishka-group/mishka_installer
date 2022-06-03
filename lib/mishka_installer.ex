defmodule MishkaInstaller do
  alias MishkaInstaller.PluginState

  @spec plugin_activity(String.t(), PluginState.t(), String.t(), String.t()) ::
          :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def plugin_activity(action, %PluginState{} = plugin, priority, status \\ "info") do
    MishkaInstaller.Activity.create_activity_by_start_child(
      activity_required_map("plugin", "other", action, priority, status), Map.drop(Map.from_struct(plugin), [:parent_pid])
    )
  end

  @spec dependency_activity(map, String.t(), String.t()) :: nil
  def dependency_activity(state, priority, status \\ "error") do
    MishkaInstaller.Activity.create_activity_by_start_child(
      activity_required_map("dependency", "compiling", "compiling", priority, status),
      Map.merge(state, %{
        state: Enum.map(state.state, fn item ->
          case item do
            {:error, :do_deps_compile, app, operation: operation, output: output} when is_struct(output) ->
              %{operation: operation, output: Map.from_struct(output), status: status, app: app}
            {:error, :do_deps_compile, app, operation: operation, output: output} ->
              %{operation: operation, output: output, status: status, app: app}
            value -> value
          end
      end)
    }))
    nil
  end

  @spec update_activity(map, String.t(), String.t()) :: nil
  def update_activity(state, priority, status \\ "error") do
    MishkaInstaller.Activity.create_activity_by_start_child(activity_required_map("dependency", "updating", "updating", priority, status), state)
    nil
  end
  def ip(user_ip), do: is_bitstring(user_ip) && user_ip || Enum.join(Tuple.to_list(user_ip), ".")

  def get_config(item, section \\ :basic) do
    case Application.fetch_env(:mishka_installer, section) do
      :error -> nil
      {:ok, list} -> Keyword.fetch!(list, item)
    end
  rescue
    _e -> nil
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

  defp activity_required_map(type, section, action, priority, status) do
    %{
      type: type,
      section: section,
      section_id: nil,
      action: action,
      priority: priority,
      status: status,
      user_id: nil
    }
  end
end
