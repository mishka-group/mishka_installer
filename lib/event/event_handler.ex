defmodule MishkaInstaller.Event.EventHandler do
  use GenServer
  require Logger

  ################################################################################
  ######################## (▰˘◡˘▰) Init data (▰˘◡˘▰) #######################
  ################################################################################
  def start_link(state \\ []) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @impl true
  @spec init(keyword()) :: {:ok, keyword()}
  def init(state \\ []) do
    {:ok, state}
  end
end
