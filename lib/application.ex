defmodule MishkaInstaller.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: MishkaInstaller.PubSub}
      ] ++ supervised_children()

    opts = [strategy: :one_for_one, name: MishkaInstaller.Supervisor]
    Supervisor.start_link(children, opts)
  end

  if Mix.env() == :test do
    def supervised_children() do
      []
    end
  else
    def supervised_children() do
      [MishkaInstaller.Event.EventHandler, MishkaInstaller.MnesiaRepo]
    end
  end
end
