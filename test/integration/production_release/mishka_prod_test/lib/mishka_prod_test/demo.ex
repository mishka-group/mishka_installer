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

  def status_line do
    started? = String.to_atom(@app) in Enum.map(Application.started_applications(), &elem(&1, 0))
    record? = not is_nil(Installer.get(:app, @app))
    hello = if Code.ensure_loaded?(@module), do: apply(@module, :hello, []), else: :not_loaded
    IO.puts("STATUS started?=#{started?} record?=#{record?} hello=#{hello}")
  end
end
