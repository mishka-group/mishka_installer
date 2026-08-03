defmodule MishkaProdTest.Demo do
  @moduledoc false
  # Driven over `bin/mishka_prod_test rpc` by run.sh: install the pre-staged ebin, then report status.
  alias MishkaInstaller.Installer.{Installer, LibraryHandler}

  @app "demo_plugin"
  @version "0.1.0"
  @module DemoPlugin

  def install_cli do
    pkg = "#{LibraryHandler.extensions_path()}/#{@app}-#{@version}"

    case Installer.install(%{app: @app, version: @version, path: pkg}) do
      {:ok, _} -> IO.puts("INSTALL_OK")
      other -> IO.puts("INSTALL_ERR #{inspect(other)}")
    end
  end

  def disable_cli do
    case MishkaInstaller.Event.Event.stop(:name, MishkaProdTest.DurablePlugin, false) do
      {:ok, plugin} -> IO.puts("DISABLE_OK #{plugin.status}")
      other -> IO.puts("DISABLE_ERR #{inspect(other)}")
    end
  end

  def disable_and_halt do
    MishkaInstaller.Event.Event.stop(:name, MishkaProdTest.DurablePlugin, false)
    :erlang.halt(0)
  end

  def plugin_line do
    plugin = MishkaInstaller.Event.Event.get(:name, MishkaProdTest.DurablePlugin)
    IO.puts("PLUGIN status=#{plugin && plugin.status} id=#{plugin && plugin.id}")
  end

  def status_line do
    started? = String.to_atom(@app) in Enum.map(Application.started_applications(), &elem(&1, 0))
    record? = not is_nil(Installer.get(:app, @app))
    hello = if Code.ensure_loaded?(@module), do: apply(@module, :hello, []), else: :not_loaded
    IO.puts("STATUS started?=#{started?} record?=#{record?} hello=#{hello}")
  end
end
