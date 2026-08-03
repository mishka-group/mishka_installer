defmodule MishkaProdTest.Application do
  @moduledoc false
  use Application

  # mishka_installer starts its own supervision tree (MnesiaRepo/EventHandler/CompileHandler); the
  # host only supervises its own plugin, which registers itself on boot.
  @impl true
  def start(_type, _args) do
    Supervisor.start_link([MishkaProdTest.DurablePlugin],
      strategy: :one_for_one,
      name: MishkaProdTest.Supervisor
    )
  end
end
