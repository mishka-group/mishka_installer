defmodule MishkaProdTest.Application do
  @moduledoc false
  use Application

  # mishka_installer starts its own supervision tree (MnesiaRepo/EventHandler/CompileHandler); the
  # host only needs to depend on it, so this tree is empty.
  @impl true
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: MishkaProdTest.Supervisor)
  end
end
