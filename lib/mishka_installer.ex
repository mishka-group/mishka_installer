defmodule MishkaInstaller do
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
end
