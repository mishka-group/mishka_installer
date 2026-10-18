# A request through a Plug pipeline whose hook point is `Hook.call/3`, the way a host runs its plugins:
# the response shows which plugins of the event ran, so each lifecycle step is read from the response.
defmodule MishkaInstallerTest.Event.RequestFlowTest.FirstPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "web:request:flow_test", initial: %{priority: 1}

  @impl true
  def call(conn),
    do: {:reply, Plug.Conn.update_resp_header(conn, "x-flow", "first", &"#{&1},first")}
end

defmodule MishkaInstallerTest.Event.RequestFlowTest.SecondPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook,
    event: "web:request:flow_test",
    initial: %{priority: 2, depends: [MishkaInstallerTest.Event.RequestFlowTest.FirstPlugin]}

  @impl true
  def call(conn),
    do: {:reply, Plug.Conn.update_resp_header(conn, "x-flow", "second", &"#{&1},second")}
end

defmodule MishkaInstallerTest.Event.RequestFlowTest.BrokenPlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "web:request:broken_flow_test"

  @impl true
  def call(_conn), do: raise("a plugin bug")
end

defmodule MishkaInstallerTest.Event.RequestFlowTest.GatePlugin do
  @moduledoc false
  use MishkaInstaller.Event.Hook, event: "web:request:gate_test"

  @impl true
  def call(conn) do
    if conn.params["token"] == "open" do
      {:reply, conn}
    else
      {:reply, :halt, conn |> Plug.Conn.send_resp(403, "refused") |> Plug.Conn.halt()}
    end
  end
end

defmodule MishkaInstallerTest.Event.RequestFlowTest.Router do
  @moduledoc false
  use Plug.Router
  alias MishkaInstaller.Event.Hook

  plug(Plug.Parsers, parsers: [:urlencoded])
  plug(:match)
  plug(:gate)
  plug(:dispatch)

  get "/page" do
    conn
    |> then(&Hook.call("web:request:flow_test", &1))
    |> send_resp(200, "page")
  end

  get "/broken" do
    conn
    |> then(&Hook.call("web:request:broken_flow_test", &1))
    |> send_resp(200, "page")
  end

  get "/guarded" do
    send_resp(conn, 200, "secret")
  end

  def gate(%Plug.Conn{request_path: "/guarded"} = conn, _opts),
    do: Hook.call("web:request:gate_test", conn)

  def gate(conn, _opts), do: conn
end

defmodule MishkaInstallerTest.Event.RequestFlowTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog, only: [capture_log: 1]
  import Plug.Test, only: [conn: 2]
  alias MishkaInstaller.Event.{Event, EventHandler, ModuleStateCompiler}
  alias MishkaInstaller.MnesiaRepo
  alias MishkaInstallerTest.Event.RequestFlowTest.{BrokenPlugin, FirstPlugin, GatePlugin}
  alias MishkaInstallerTest.Event.RequestFlowTest.{Router, SecondPlugin}

  @events ["web:request:flow_test", "web:request:broken_flow_test", "web:request:gate_test"]

  setup do
    :persistent_term.put(:compile_status, "ready")
    tmp = Path.join(System.tmp_dir!(), "mishka-flow-#{System.unique_integer([:positive])}")
    Application.put_env(:mishka_installer, MnesiaRepo, mnesia_dir: tmp, essential: [Event])

    on_exit(fn ->
      for name <- [MnesiaRepo, EventHandler] do
        pid = Process.whereis(name)
        if is_pid(pid) and Process.alive?(pid), do: GenServer.stop(name)
      end

      ModuleStateCompiler.purge(@events)
      File.rm_rf!(tmp)
    end)

    MishkaInstaller.subscribe("mnesia")
    start_supervised!(EventHandler)
    start_supervised!(MnesiaRepo)
    assert_receive %{status: :synchronized, channel: "mnesia"}
    assert_receive %{status: :event_status, channel: "mnesia", data: "ready"}

    :ok
  end

  describe "plugins of an event in a request ===>" do
    test "a request runs the started plugins in order, and a stopped plugin leaves the chain" do
      assert flow_header(request("/page")) == []

      start_plugins([FirstPlugin, SecondPlugin])
      compile("web:request:flow_test")

      conn = request("/page")
      assert conn.status == 200
      assert flow_header(conn) == ["first,second"]

      {:ok, %{status: :stopped}} = Event.stop(:name, SecondPlugin, false)
      assert flow_header(request("/page")) == ["first"]

      {:ok, %{status: status}} = Event.enable(SecondPlugin, false)
      assert status in [:restarted, :started]
      assert flow_header(request("/page")) == ["first,second"]

      {:ok, _} = Event.stop(:name, FirstPlugin, false)
      assert flow_header(request("/page")) == []
      assert Event.get(:name, SecondPlugin).status == :held
    end

    test "unregistering the plugins of an event ends their part in the request" do
      start_plugins([FirstPlugin, SecondPlugin])
      compile("web:request:flow_test")
      assert flow_header(request("/page")) == ["first,second"]

      {:ok, _} = Event.unregister(:event, "web:request:flow_test", false)
      assert flow_header(request("/page")) == []
    end

    @tag :capture_log
    test "a plugin that raises costs the request nothing" do
      start_plugins([BrokenPlugin])
      compile("web:request:broken_flow_test")

      log = capture_log(fn -> assert request("/broken").status == 200 end)
      assert log =~ "plugin pipeline raised"
    end

    test "a gate plugin refuses the request before the page is served" do
      start_plugins([GatePlugin])
      compile("web:request:gate_test")

      refused = request("/guarded")
      assert refused.status == 403
      assert refused.resp_body == "refused"

      opened = request("/guarded?token=open")
      assert opened.status == 200
      assert opened.resp_body == "secret"
    end

    test "requests that arrive while the event is recompiled always see a whole chain" do
      start_plugins([FirstPlugin, SecondPlugin])
      compile("web:request:flow_test")

      requests =
        Task.async_stream(1..120, fn round ->
          if rem(round, 10) == 0, do: toggle(SecondPlugin, rem(div(round, 10), 2) == 0)
          request("/page")
        end)

      for {:ok, conn} <- requests do
        assert conn.status == 200
        assert flow_header(conn) in [["first"], ["first,second"]]
      end
    end
  end

  defp request(path), do: path |> then(&conn(:get, &1)) |> Router.call(Router.init([]))

  defp flow_header(conn), do: Plug.Conn.get_resp_header(conn, "x-flow")

  defp toggle(plugin, true), do: Event.enable(plugin, false)
  defp toggle(plugin, false), do: Event.stop(:name, plugin, false)

  defp compile(event), do: :ok = EventHandler.do_compile(event, :start, false)

  defp start_plugins(plugins) do
    for plugin <- plugins do
      start_supervised!(plugin)
      eventually(fn -> status(plugin) in [:started, :restarted] end)
    end
  end

  defp status(plugin) do
    case Event.get(:name, plugin) do
      %{status: status} -> status
      _ -> nil
    end
  end

  defp eventually(fun, tries \\ 150)
  defp eventually(_fun, 0), do: flunk("condition was never met")

  defp eventually(fun, tries),
    do: if(fun.(), do: :ok, else: Process.sleep(20) && eventually(fun, tries - 1))
end
