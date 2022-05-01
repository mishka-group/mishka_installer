defmodule MishkaInstaller.Installer.DepChangesProtector do
  use GenServer
  require Logger

  @spec start_link(list()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def push(app, status) do
    GenServer.cast(__MODULE__, {:push, app: app, status: status})
  end

  @impl true
  def init(stack) do
    Logger.info("OTP Dependencies changes protector Cache server was started")
    {:ok, stack}
  end

  def check_josn_file_exist?() do
    # TODO: Check if extension json file does not exist, create it with database
  end

  def is_there_update?() do
    # TODO: Check is there update from a developer json url, and get it from plugin/componnet mix file, Consider queue
  end

  def is_dependency_compiling?() do
    # TODO: Create queue for installing multi deps, and compiling, check oban: https://github.com/sorentwo/oban
  end
end
