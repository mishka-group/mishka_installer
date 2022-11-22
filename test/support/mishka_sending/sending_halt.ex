defmodule MishkaSendingEmailPlugin.SendingHalt do
  @moduledoc false
  # This module was just made for testing
  alias MishkaSendingEmailPlugin.TestEvent

  use MishkaInstaller.Hook,
    module: __MODULE__,
    behaviour: TestEvent,
    event: :on_test_event,
    initial: []

  def initial(args) do
    Logger.warn("SendingHalt plugin was started")

    event = %PluginState{
      name: "MishkaSendingEmailPlugin.SendingHalt",
      event: Atom.to_string(@ref),
      priority: 2
    }

    Hook.register(event: event)
    {:ok, @ref, args}
  end

  def call(%TestEvent{} = state) do
    new_state =
      if state.ip == "128.0.1.1",
        do: Map.merge(state, %{ip: "129.0.1.1", private: %{acl: 1}}),
        else: state

    {:reply, :halt, new_state}
  end
end
