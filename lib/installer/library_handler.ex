defmodule MishkaInstaller.Installer.LibraryHandler do
  @moduledoc """
  This module provides programmers with a public APIs and helpers that allow them to
  construct their own custom functions.

  > It also includes aids and tools that allow them to work with the library while it is running.

  `MishkaInstaller.Installer.Installer` is also referred to as action and aggregator functions,
  which is something that should be taken into consideration.

  If you are unsure about the responsibilities of each function,
  it is recommended that you utilise the `MishkaInstaller.Installer.Installer` module and its functions,
  which consist of a collection of predefined strategies.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  > #### Use cases information {: .tip}
  >
  > Especially when you want to work with a library that depends on a large number
  > of other libraries or vice versa, each of the functions of this file has its own
  > requirements that must be taken into consideration.
  """
  alias MishkaInstaller.Installer.{Installer, Collect}

  @type posix :: :file.posix()

  @type io_device :: :file.io_device()

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map() | binary() | list(any())}

  @type app :: Installer.t() | map()

  @type runtime_type :: :add | :force_update | :uninstall

  @type compile_time_type :: :cmd | :port | :mix

  ####################################################################################
  ######################## (▰˘◡˘▰) Public API (▰˘◡˘▰) ##########################
  ####################################################################################
  @doc """
  This particular function executes the necessary instructions in order to download the
  dependencies, compile the dependencies, and compile the project itself.

  - In the present version, there are two options that are available, namely `Port` and `System`.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ```elixir
  alias MishkaInstaller.Installer.{Installer, LibraryHandler}

  do_compile(%Installer{app: "some_name", path: "some_name", type: :hex})
  ```

  **During the subsequent releases, we will make an effort to incorporate the `script` mode**.
  - Based on: https://elixirforum.com/t/12114/14
  """
  @spec do_compile(app) :: :ok | error_return()
  def do_compile(app) when app.compile_type in [:cmd, :port, :mix] do
    with ext_path <- extensions_path(),
         :ok <- change_dir("#{ext_path}/#{app.app}-#{app.version}"),
         :ok <- command_execution(app.compile_type, "deps.get"),
         :ok <- command_execution(app.compile_type, "deps.compile"),
         :ok <- command_execution(app.compile_type, "compile") do
      :ok
    end
  after
    File.cd!(MishkaInstaller.__information__().path)
  end

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
  A helper function to extract downloaded libraries from `hex.pm`, `github` and custom `url`.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  extract(:tar, a_path, "app_name-version")
  ```
  """
  @spec extract(:tar, binary(), String.t()) :: :ok | error_return()
  def extract(:tar, archived, name) do
    temp_path = ~c'#{extensions_path()}/temp-#{name}'

    :erl_tar.extract(~c'#{archived}', [:compressed, {:cwd, ~c'#{temp_path}'}])
    |> case do
      :ok ->
        files_list = File.ls!(temp_path)

        if "mix.exs" in files_list do
          File.rename(temp_path, ~c'#{extensions_path()}/#{name}')
          :ok
        else
          dirs_list =
            File.ls!(temp_path)
            |> Enum.filter(&File.dir?("#{extensions_path()}/temp-#{name}/#{&1}"))

          finding_mix =
            Enum.find(
              dirs_list,
              &("mix.exs" in File.ls!("#{extensions_path()}/temp-#{name}/#{&1}"))
            )

          if is_nil(finding_mix) do
            message =
              "There is a problem in extracting the compressed file of the ready-made library."

            {:error,
             [%{message: message, field: :path, action: :extract, source: :bad_structure}]}
          else
            temp_file_path = "#{extensions_path()}/temp-#{name}/#{finding_mix}"

            case File.rename(temp_file_path, "#{extensions_path()}/#{name}") do
              :ok ->
                File.rm_rf!("#{extensions_path()}/temp-#{name}")
                :ok

              {:error, source} ->
                File.rm_rf!("#{extensions_path()}/temp-#{name}")
                message = "There was a problem moving the file."
                {:error, [%{message: message, field: :path, action: :extract, source: source}]}
            end
          end
        end

      {:error, term} ->
        message =
          "There is a problem in extracting the compressed file of the ready-made library."

        {:error, [%{message: message, field: :path, action: :move, source: term}]}
    end
  end

  @doc """
  Helper function to transfer files to the deployment path.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  move(app, "archived_file_binary")
  ```
  """
  @spec move(Installer.t(), binary() | Path.t()) :: okey_return() | error_return()
  def move(app, archived_file) do
    with {:mkdir_p, :ok} <- {:mkdir_p, File.mkdir_p(extensions_path())},
         {:ok, path} <- write_downloaded_lib(app, archived_file) do
      {:ok, path}
    else
      {:mkdir_p, {:error, error}} ->
        message = "An error occurred in downloading and transferring the library file you want."
        {:error, [%{message: message, field: :path, action: :move, source: error}]}

      error ->
        error
    end
  end

  @doc """
  Helper function to transfer and replace built libs to the project `_build` dir.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  alias MishkaInstaller.Installer.{Installer, LibraryHandler}

  move_and_replace_build_files(%Installer{app: "some_name", path: "some_name", type: :hex})
  ```
  """
  @spec move_and_replace_build_files(Installer.t()) :: okey_return() | error_return()
  def move_and_replace_build_files(app) do
    path = extensions_path()
    info = MishkaInstaller.__information__()
    build_path = "#{path}/#{app.app}-#{app.version}/_build/#{info.env}/lib"
    root_build = "#{info.path}/_build/#{info.env}/lib"

    moved_files =
      File.ls!(build_path)
      |> Enum.reduce([], fn sub_app, acc ->
        with app_build <- "#{build_path}/#{sub_app}/ebin/#{sub_app}.app",
             {:ok, properties} <- read_app(String.to_atom(sub_app), app_build),
             :ok <- compare_version_with_installed_app(String.to_atom(sub_app), properties[:vsn]),
             sub_path <- "#{info.path}/_build/#{info.env}/lib/#{sub_app}",
             :ok <- Installer.uninstall(String.to_atom(sub_app), sub_path) do
          destination_path = Path.join(root_build, Path.basename("#{build_path}/#{sub_app}"))
          File.cp_r("#{build_path}/#{sub_app}", destination_path)
          acc ++ [{String.to_atom(sub_app), destination_path <> "/ebin"}]
        else
          _ -> acc
        end
      end)

    if moved_files != [] and !is_tuple(moved_files) do
      {:ok, moved_files}
    else
      message = "There is no app to be replicated in the requested path."
      {:error, [%{message: message, field: :app, action: :move_and_replace_build_files}]}
    end
  end

  @doc """
  Helper function that executes system and script commands.


  #### Ref:

  * https://hexdocs.pm/elixir/Port.html#module-spawn_executable
  * https://elixirforum.com/t/48336/

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  command_execution(:cmd, "deps.get")

  command_execution(:port, "deps.get")
  ```
  """
  @spec command_execution(:cmd | :port, String.t(), String.t()) :: :ok | error_return()
  def command_execution(type, command, operation \\ "mix")

  def command_execution(:cmd, command, operation) do
    info = MishkaInstaller.__information__()

    {stream, status} =
      System.cmd(operation, [command],
        into: %Collect{
          callback: fn line, _acc ->
            MishkaInstaller.broadcast("installer", :cmd_messaging, %{
              operation: command,
              message: "#{inspect(line)}",
              status: :looping
            })

            IO.puts("[stdout] #{line}")
          end
        },
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "#{info.env}"}, {"PROJECT_PATH", "#{info.path}"}]
      )

    return_exist = %{operation: command, output: stream, status: status}
    MishkaInstaller.broadcast("installer", :cmd_stopped, return_exist)

    if status == 0 do
      :ok
    else
      message = "There is a pre-ready error when executing the system command."
      source = %{command: command, output: stream}
      {:error, [%{message: message, field: :cmd, action: :command_execution, source: source}]}
    end
  end

  def command_execution(:port, command, operation) do
    info = MishkaInstaller.__information__()
    path = System.find_executable("#{operation}")

    port =
      Port.open({:spawn_executable, path}, [
        :binary,
        :exit_status,
        args: [command],
        line: 1000,
        env: [{~c"MIX_ENV", ~c"#{info.env}"}, {~c"PROJECT_PATH", ~c"#{info.path}"}]
      ])

    start_exec_satet([])
    %{status: status, output: output} = loop(port, command)

    if status == 0 do
      :ok
    else
      message = "There is a pre-ready error when executing the system command as a Port."
      source = %{command: command, output: output}
      {:error, [%{message: message, field: :port, action: :command_execution, source: source}]}
    end
  end

  # Based on: https://elixirforum.com/t/12114/14
  def command_execution(:mix, command, _operation) do
    message = "We do not support it at the moment, it may be included in future versions."
    source = %{command: command, output: nil}
    {:error, [%{message: message, field: :port, action: :command_execution, source: source}]}
  end

  @doc """
  Helper function to read Erlang `.app` file in Elixir.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ## Example:

  ```elixir
  consult_app_file(bin_path)
  ```
  """
  @spec consult_app_file(Path.t()) :: {:ok, term()} | {:error, any()}
  def consult_app_file(bin) do
    # The path could be located in an .ez archive, so we use the prim loader.
    with {:ok, tokens, _} <- :erl_scan.string(String.to_charlist(bin)) do
      :erl_parse.parse_term(tokens)
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
  Helper function to load an application and all its dependencies.

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
    with {:load, :ok} <- {:load, Application.load(app_name)},
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
  Helper function to get download path and extract runtime libraries.

  ## Example:

  ```elixir
  extensions_path()
  ```
  """
  @spec extensions_path() :: Path.t()
  def extensions_path() do
    info = MishkaInstaller.__information__()
    Path.join(info.path, ["deployment/", "#{info.env}/", "extensions"])
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Callback (▰˘◡˘▰) ##########################
  ####################################################################################
  defp start_exec_satet(initial_value),
    do: Agent.start_link(fn -> initial_value end, name: __MODULE__)

  defp update_exec_satet(new_value),
    do: Agent.get_and_update(__MODULE__, fn state -> {state, state ++ new_value} end)

  defp get_exec_state(), do: Agent.get(__MODULE__, & &1)

  defp stop_exec_state(), do: Agent.stop(__MODULE__)
  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  defp write_downloaded_lib(app, archived_file) do
    open_file =
      File.open("#{extensions_path()}/#{app.app}-#{app.version}.tar", [:read, :write], fn file ->
        IO.binwrite(file, archived_file)
        File.close(file)
      end)

    case open_file do
      {:ok, _ress} ->
        {:ok, "#{extensions_path()}/#{app.app}-#{app.version}.tar"}

      error ->
        message = "An error occurred in downloading and transferring the library file you want."
        {:error, [%{message: message, field: :path, action: :move, source: error}]}
    end
  end

  defp change_dir(path) do
    case File.cd(path) do
      {:error, posix} ->
        message = "No such directory exists or you do not have access to it."
        {:error, [%{message: message, field: :path, action: :rename_dir, source: posix}]}

      _ ->
        :ok
    end
  end

  defp loop(port, command) do
    receive do
      {^port, {:data, {:eol, msg}}} when is_binary(msg) ->
        update_exec_satet([msg])

        MishkaInstaller.broadcast("installer", :port_messaging, %{
          operation: command,
          message: msg,
          status: :looping
        })

        IO.puts("[stdout] #{inspect(msg)}")
        loop(port, command)

      {^port, {:data, data}} ->
        update_exec_satet([data])

        MishkaInstaller.broadcast("installer", :port_messaging, %{
          operation: command,
          message: data,
          status: :looping
        })

        IO.puts("[stdout] #{inspect(data)}")
        loop(port, command)

      {^port, {:exit_status, exit_status}} ->
        output = get_exec_state()
        stop_exec_state()
        return_exist = %{operation: command, output: output, status: exit_status}
        MishkaInstaller.broadcast("installer", :port_stopped, return_exist)
        return_exist
    end
  end

  defp compare_version_with_installed_app(app, version) do
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
end
