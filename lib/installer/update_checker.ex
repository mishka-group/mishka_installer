defmodule MishkaInstaller.Installer.UpdateChecker do
  use GenServer, restart: :permanent
  require Logger
  @update_check_time 300_000
  alias MishkaInstaller.Installer.DepHandler
  alias MishkaInstaller.Helper.Sender

  @spec start_link(list()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec get(String.t()) :: map()
  def get(app) do
    GenServer.call(__MODULE__, {:get, app})
  end

  @spec get :: [map()]
  def get() do
    GenServer.call(__MODULE__, :get)
  end

  @impl true
  def init(state) do
    Logger.info("OTP UpdateChecker server was started")
    {:ok, state, {:continue, :start_task}}
  end

  @impl true
  def handle_continue(:start_task, state) do
    Process.send_after(self(), :check_update, @update_check_time)
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_update, state) do
    Logger.info("OTP UpdateChecker check update tasks were sent.")
    Process.send_after(self(), :check_update, @update_check_time)
    {:noreply, check_apps_update(state)}
  end

  @impl true
  def handle_call({:get, app}, _from, state) do
    {:reply, Enum.find(state, & &1.app == app), state}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @spec check_apps_update([map()]) :: [map()]
  def check_apps_update(state) do
    DepHandler.read_dep_json()
    |> create_update_task()
  rescue
    _e ->
      MishkaInstaller.update_activity(%{action: :check_apps_update, status: :extension_json_file}, "high")
      state
  end

  defp create_update_task({:ok, :read_dep_json, apps}) do
    apps
    |> Enum.map(&(Task.async(fn -> create_update_url(&1) end)))
    |> Enum.reject(& is_nil(&1))
    |> Enum.map(&Task.await/1)
  end

  defp create_update_url(%{"type" => type} = app) when type in ["hex", "git"] do
    case Sender.package(type, app) do
      {:ok, :package, %{"latest_stable_version" => version} = _package} = _data when not is_nil(version) ->
        if Version.parse(version) != :error do
          %{app: app["app"], latest_stable_version: version, current_version: app["version"]}
        else
          MishkaInstaller.update_activity(%{app: app["app"], type: type, status: :server_bad_version}, "high")
        end
      {:error, :package, status} ->
        MishkaInstaller.update_activity(%{app: app["app"], type: type, status: status}, "high")
      _ ->
        MishkaInstaller.update_activity(%{app: app["app"], type: type, status: :server_error}, "high")
    end
  end

  defp create_update_url(_app), do: nil
end
