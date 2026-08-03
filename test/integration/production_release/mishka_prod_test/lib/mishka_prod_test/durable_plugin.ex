defmodule MishkaProdTest.DurablePlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "prod_durable_evt", initial: %{priority: 10}

  @impl true
  def call(state), do: {:reply, state}
end
