defmodule MishkaInstaller.Installer.LibraryHandler do
  @moduledoc """
  This module provides programmers with a public APIs and helpers that allow them to
  load a **pre-built** Elixir/Erlang library (its compiled `ebin`) into a running system.

  > It also includes aids and tools that allow them to work with the library while it is running.

  `MishkaInstaller.Installer.Installer` is also referred to as action and aggregator functions,
  which is something that should be taken into consideration.

  If you are unsure about the responsibilities of each function,
  it is recommended that you utilise the `MishkaInstaller.Installer.Installer` module and its functions,
  which consist of a collection of predefined strategies.

  ## Why only the `ebin`?

  Compiling a library at runtime (`mix deps.get`/`deps.compile`/`compile`) **cannot** work in a
  production `release`, because a release ships **no** `Mix`, **no** `Hex`, **no** project source
  and **no** `_build` tree. So instead of compiling, this module loads the **already compiled**
  artifacts (`ebin/*.beam` + `ebin/<app>.app`):

  1. add the `ebin` directory to the code path (`Code.prepend_path/1`),
  2. `Application.load/1` + `Application.ensure_all_started/1`.

  > #### Restart consideration {: .info}
  >
  > The code path is held **in memory** by the Erlang code server and is **not** persisted across a
  > restart. Only the files on disk and the `MishkaInstaller.Installer.Installer` Mnesia record
  > survive. The path + load **must be replayed on every boot** (see
  > `MishkaInstaller.Installer.CompileHandler`).

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > Loading a `.beam` is **running arbitrary code with full node privileges**; the BEAM has no
  > sandbox. Only load artifacts from a trusted source, built for the **same** Erlang/OTP and
  > Elixir as the host. Native code (`NIF`/port driver `.so`/`.dll`) is **not** portable across
  > OS/architecture/ERTS.
  """
  alias MishkaInstaller.Installer.Installer

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map() | binary() | list(any())}

  @type app :: Installer.t() | map()

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @doc """
  By means of this helper function, identify the paths of dependencies to the Erlang VM.

  For more information see `Code.prepend_path/1`.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  files_list = [
    decimal: "/_build/dev/lib/decimal/ebin",
    ecto: "/_build/dev/lib/ecto/ebin",
    uniq: "/_build/dev/lib/uniq/ebin"
  ]

  prepend_compiled_apps(files_list)
  ```
  """
  @spec prepend_compiled_apps(list(tuple())) :: :ok | error_return()
  def prepend_compiled_apps(files_list) do
    prepend =
      Enum.reduce(files_list, [], fn {app_name, path}, acc ->
        if Code.prepend_path(path), do: acc, else: acc ++ [{app_name, path}]
      end)

    if prepend == [] do
      :ok
    else
      message = "Some routes cannot be prepended."

      {:error,
       [%{message: message, field: :path, action: :prepend_compiled_apps, source: prepend}]}
    end
  end

  @doc """
  Helper function to read Erlang `.app` file in Elixir.

  Reads the given app from path in an optimized format and returns its contents.

  Based on:
  https://github.com/elixir-lang/elixir/blob/f0fcd64f937af8ccdd98e086c107c3902485d404/lib/mix/lib/mix/app_loader.ex#L59-L75


  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  read_app(:mishka_developer_tools, app_bin_path)
  ```
  """
  @spec read_app(atom(), Path.t()) :: {:ok, any()} | error_return()
  def read_app(app, app_path) do
    case File.read(app_path) do
      {:ok, bin} ->
        with {:ok, tokens, _} <- :erl_scan.string(String.to_charlist(bin)),
             {:ok, {:application, ^app, properties}} <- :erl_parse.parse_term(tokens) do
          {:ok, properties}
        else
          {:ok, _data} ->
            message = "The sent app is in conflict with the path of the ebin file."
            {:error, [%{message: message, field: :erl_scan, action: :read_app}]}

          error ->
            message = "There is a problem in parsing the application."
            {:error, [%{message: message, field: :erl_scan, action: :read_app, source: error}]}
        end

      {:error, error} ->
        message =
          "The path sent from the ebin file is not correct or you do not have access to it."

        {:error, [%{message: message, field: :ebin_path, action: :read_app, source: error}]}
    end
  end

  @doc """
  Extracts a downloaded **pre-built** artifact (a `tar.gz` whose content is a compiled `ebin`)
  into the extensions directory under the canonical `name` (e.g. `"<app>-<version>"`).

  The archive may contain `ebin/...` at its top level or nested one directory deep
  (for example `<app>-<version>/ebin/...`). Nothing is compiled here.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  extract(:tar, tar_gz_binary, "elixir_uuid-1.2.1")
  ```
  """
  @spec extract(:tar, binary(), String.t()) :: :ok | error_return()
  def extract(:tar, archived, name) do
    base = extensions_path()
    temp_path = "#{base}/temp-#{name}"
    File.rm_rf!(temp_path)
    File.mkdir_p!(temp_path)

    :erl_tar.extract({:binary, archived}, [:compressed, {:cwd, String.to_charlist(temp_path)}])
    |> case do
      :ok ->
        finalize_extract(temp_path, "#{base}/#{name}")

      error ->
        File.rm_rf!(temp_path)
        message = "There is a problem in extracting the compressed file of the pre-built library."
        {:error, [%{message: message, field: :path, action: :extract, source: error}]}
    end
  end

  @doc """
  Helper function to load an application and all its dependencies.

  > It is idempotent: an already loaded application is treated as a success, so this is safe to
  > call again on every boot when re-activating a previously installed library.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  application_ensure(:mishka_developer_tools)
  ```
  """
  @spec application_ensure(atom()) :: :ok | error_return()
  def application_ensure(app_name) do
    load =
      case Application.load(app_name) do
        :ok -> :ok
        {:error, {:already_loaded, ^app_name}} -> :ok
        error -> error
      end

    with {:load, :ok} <- {:load, load},
         :ok <- load_modules(app_name),
         {:all, {:ok, _apps}} <- {:all, Application.ensure_all_started(app_name)} do
      :ok
    else
      {:load, error} ->
        message = "There was an error loading the application you are looking for."
        {:error, [%{message: message, field: :app, action: :application_ensure, source: error}]}

      {:all, {:error, error}} ->
        message =
          "An error occurred in loading the application in the sub-set and related to the application you sent."

        {:error, [%{message: message, field: :app, action: :application_ensure, source: error}]}
    end
  end

  # Releases boot in embedded mode (no on-demand auto-loading), so explicitly load the installed
  # app's not-yet-loaded modules from the prepended ebin before starting it.
  defp load_modules(app_name) do
    for module <- Application.spec(app_name, :modules) || [], !:code.is_loaded(module) do
      :code.load_file(module)
    end

    :ok
  end

  @doc """
  Helper function to unload an application.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  unload(:mishka_developer_tools)
  ```
  """
  @spec unload(atom()) :: :ok | error_return()
  def unload(app) do
    case Application.unload(app) do
      {:error, {:not_loaded, ^app}} ->
        :ok

      {:error, error} ->
        message = "An error occurred in deactivating the app."
        {:error, [%{message: message, field: :app, action: :unload, source: error}]}

      _ ->
        :ok
    end
  end

  @doc """
  Helper function to get the path where the pre-built runtime libraries (extensions) are stored.

  > It defaults to `deployment/<env>/extensions` under the project path and can be overridden with
  > the `:extensions_path` **application env** so a production release can point it at a **writable**
  > volume outside the (read-only) release directory.

  ## Example:

  ```elixir
  extensions_path()
  ```
  """
  @spec extensions_path() :: Path.t()
  def extensions_path() do
    info = MishkaInstaller.__information__()

    case Application.get_env(:mishka_installer, :extensions_path) do
      nil -> Path.join(info.path, ["deployment/", "#{info.env}/", "extensions"])
      path -> path
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  @doc false
  @spec compare_version_with_installed_app(atom(), String.t()) :: :ok | error_return()
  def compare_version_with_installed_app(app, version) do
    ver = Application.spec(app, :vsn)

    cond do
      is_nil(ver) ->
        :ok

      Version.compare("#{version}", "#{ver}") == :gt ->
        :ok

      true ->
        message =
          "In the path of installed apps, there is an app of the same name with the same or higher version."

        {:error, [%{message: message, field: :app, action: :compare_version_with_installed_app}]}
    end
  end

  defp finalize_extract(temp_path, dest) do
    if ebin_dir?(temp_path) do
      move_extracted(temp_path, dest)
    else
      sub = Enum.find(File.ls!(temp_path), &ebin_dir?("#{temp_path}/#{&1}"))

      if is_nil(sub) do
        File.rm_rf!(temp_path)
        message = "The downloaded package does not contain a compiled `ebin` directory."
        {:error, [%{message: message, field: :path, action: :extract, source: :bad_structure}]}
      else
        result = move_extracted("#{temp_path}/#{sub}", dest)
        File.rm_rf!(temp_path)
        result
      end
    end
  end

  defp ebin_dir?(path) do
    File.dir?("#{path}/ebin") and
      Enum.any?(File.ls!("#{path}/ebin"), &String.ends_with?(&1, ".app"))
  end

  defp move_extracted(from, dest) do
    File.rm_rf!(dest)

    case File.rename(from, dest) do
      :ok ->
        :ok

      {:error, source} ->
        message = "There was a problem moving the extracted package."
        {:error, [%{message: message, field: :path, action: :extract, source: source}]}
    end
  end
end
