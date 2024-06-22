defmodule MishkaInstaller do
  if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) do
    @project_env Mix.env()
  else
    @project_env nil
  end

  @moduledoc false
  def broadcast(channel, status, data, broadcast \\ true) do
    if broadcast do
      MishkaInstaller.PubSub
      |> Phoenix.PubSub.broadcast("mishka:plugin:#{channel}", %{
        status: status,
        channel: channel,
        data: data
      })
    else
      :ok
    end
  end

  @doc false
  def subscribe(channel) do
    Phoenix.PubSub.subscribe(MishkaInstaller.PubSub, "mishka:plugin:#{channel}")
  end

  @doc false
  def unsubscribe(channel) do
    Phoenix.PubSub.unsubscribe(MishkaInstaller.PubSub, "mishka:plugin:#{channel}")
  end

  def __information__() do
    %{
      path: System.get_env("PROJECT_PATH") || Application.get_env(:mishka, :project_path),
      env: System.get_env("MIX_ENV") || Application.get_env(:mishka, :project_env) || @project_env
    }
  end
end
