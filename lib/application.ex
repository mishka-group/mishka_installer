defmodule MishkaInstaller.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: MishkaInstaller.PubSub}
      # MishkaInstaller.MnesiaRepo
    ]

    opts = [strategy: :one_for_one, name: MishkaInstaller.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
