defmodule MishkaInstaller.PluginStateDynamicSupervisor do
  @moduledoc """
  This module supervises the states created during the registration of each plugin.

  ## Module communication process of this module

  ```
         +------------------------------------------------+
         |                                                |
         |                                                |
  +------+  MishkaInstaller.PluginStateDynamicSupervisor  |
  |      |                                                |
  |      |                                                |
  |      +--------------------------------------+----^----+
  |                                             |    |
  |                                             |    |
  |                                             |    |
  |      +--------------------------+           |    |
  |      |                          |           |    |
  +------>  PluginStateRegistry     |           |    |
         |                          |           |    |
         +--------^-----------------+           |    |
                  |                             |    |
                  |                             |    |
                  |                             |    |
                  |                             |    |
                  |        +--------------------v----+-----+
                  |        |                               |
                  |        |  MishkaInstaller.PluginState  |
                  +--------+                               |
                           +--------------------+----------+
                                                |
                                                |
                                                |
                                                |
            +----------------------------+      |
            |                            |      |
            | MishkaInstaller.PluginETS  <------+
            |                            |
            +----------------------------+
  ```
  """

  @doc """
  Start supervising plugin States.
  """
  @spec start_job(%{id: String.t(), type: String.t(), parent_pid: any()}) ::
          :ignore | {:error, any} | {:ok, :add | :edit, pid}
  def start_job(args) do
    DynamicSupervisor.start_child(PluginStateOtpRunner, {MishkaInstaller.PluginState, args})
    |> case do
      {:ok, pid} -> {:ok, :add, pid}
      {:ok, pid, _any} -> {:ok, :add, pid}
      {:error, {:already_started, pid}} -> {:ok, :edit, pid}
      {:error, result} -> {:error, result}
    end
  end

  @doc """
  You are able to terminate all children that this module is responsible for supervising with the assistance of this function.

  ## Examples
  ```elixir
  MishkaInstaller.PluginStateDynamicSupervisor.terminate_childeren()
  ```
  """
  def terminate_childeren() do
    Enum.map(running_imports(), fn item ->
      DynamicSupervisor.terminate_child(PluginStateOtpRunner, item.pid)
    end)
  end

  @doc """
  Show all PIDs of `PluginStateDynamicSupervisor` module from `PluginStateRegistry` Registry.

  ## Examples
  ```elixir
  MishkaInstaller.PluginStateDynamicSupervisor.running_imports()
  ```
  """
  def running_imports(), do: registery()

  @doc """
  Show all PIDs of `PluginStateDynamicSupervisor` module based on a specific event from `PluginStateRegistry` Registry.

  ## Examples
  ```elixir
  MishkaInstaller.PluginStateDynamicSupervisor.running_imports("event_test_name")
  ```
  """
  def running_imports(event_name) do
    [{:==, :"$3", event_name}]
    |> registery()
  end

  defp registery(guards \\ []) do
    {match_all, map_result} = {
      {:"$1", :"$2", :"$3"},
      [%{id: :"$1", pid: :"$2", type: :"$3"}]
    }

    Registry.select(PluginStateRegistry, [{match_all, guards, map_result}])
  end

  @doc """
  Get PID based on the name of a plugin from `PluginStateRegistry` Registry.

  ## Examples
  ```elixir
  MishkaInstaller.PluginStateDynamicSupervisor.get_plugin_pid("Plugin.TestName")
  ```
  """
  @spec get_plugin_pid(String.t()) :: {:error, :get_plugin_pid} | {:ok, :get_plugin_pid, pid}
  def get_plugin_pid(module_name) do
    case Registry.lookup(PluginStateRegistry, module_name) do
      [] -> {:error, :get_plugin_pid}
      [{pid, _type}] -> {:ok, :get_plugin_pid, pid}
    end
  end
end
