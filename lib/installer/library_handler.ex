defmodule MishkaInstaller.Installer.LibraryHandler do
  @moduledoc """
  Loads a **pre-built** Elixir/Erlang library (its compiled `ebin`) into a running system, and gives
  the helpers to work with it while it is running.

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

  @default_archive_limits [max_bytes: 500 * 1024 * 1024, max_entries: 10_000]

  @tar_entry_overhead 4 * 512

  @tar_end_overhead 20 * 512

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
        with chars when is_list(chars) <- :unicode.characters_to_list(bin),
             {:ok, tokens, _} <- :erl_scan.string(chars),
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

  ## Archive limits

  Before anything is written, the archive's table is read and the whole archive is refused with
  `{:error, [%{action: :extract, field: :path, ...}]}` when:

  - its members would unpack past `:max_bytes` bytes in all (a gzip archive is also inflated only
    up to that size, so a decompression bomb stops there and never fills memory or disk);
  - it holds more than `:max_entries` members (files and directories);
  - a member is not a regular file or a directory: a symlink, a hard link, a device or a fifo;
  - a member path is absolute or climbs out with `..`.

  Both limits are options; the defaults are 500 MB and 10 000 members:

  ```elixir
  config :mishka_installer, :archive_limits,
    max_bytes: 500 * 1024 * 1024,
    max_entries: 10_000
  ```

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
    with :ok <- valid_extract_name(name) do
      extract_archive(archived, name)
    end
  end

  # `name` becomes a folder of the extensions directory, so it must be one plain path segment.
  defp valid_extract_name(name) do
    if is_binary(name) and name not in ["", ".", ".."] and name == Path.basename(name) and
         not String.contains?(name, <<0>>) do
      :ok
    else
      message = "The name of the extracted package must be a single folder name."
      {:error, [%{message: message, field: :path, action: :extract}]}
    end
  end

  defp extract_archive(archived, name) do
    base = extensions_path()
    temp_path = "#{base}/temp-#{name}"
    limits = archive_limits()

    with {:ok, tar} <- inflate_archive(archived, limits),
         :ok <- safe_tar_members(tar, limits) do
      File.rm_rf!(temp_path)
      File.mkdir_p!(temp_path)
      unpack(tar, temp_path, "#{base}/#{name}")
    end
  end

  defp unpack(tar, temp_path, dest) do
    case :erl_tar.extract({:binary, tar}, [{:cwd, String.to_charlist(temp_path)}]) do
      :ok ->
        finalize_extract(temp_path, dest)

      error ->
        File.rm_rf!(temp_path)
        message = "There is a problem in extracting the compressed file of the pre-built library."
        {:error, [extract_error(message, error)]}
    end
  end

  defp archive_limits() do
    Keyword.merge(
      @default_archive_limits,
      Application.get_env(:mishka_installer, :archive_limits, [])
    )
  end

  # A gzip archive is inflated here, a block at a time, so a small download that would inflate
  # without end is stopped at the limit instead of filling memory (`:erl_tar.table/2` with
  # `:compressed` inflates the whole binary with no limit). A plain tar is taken as it is.
  defp inflate_archive(<<0x1F, 0x8B, _::binary>> = archived, limits) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, 31, :cut)
      inflate_chunks(z, :zlib.safeInflate(z, archived), limits, 0, [])
    catch
      :error, reason ->
        {:error, [extract_error("The archive is not a readable gzip file.", reason)]}
    after
      :zlib.close(z)
    end
  end

  defp inflate_archive(archived, limits) do
    case byte_size(archived) > tar_size_limit(limits) do
      true -> {:error, [too_big_error(limits[:max_bytes])]}
      false -> {:ok, archived}
    end
  end

  defp inflate_chunks(z, {status, chunks}, limits, total, acc) do
    new_total = total + IO.iodata_length(chunks)

    case {new_total > tar_size_limit(limits), status} do
      {true, _status} ->
        {:error, [too_big_error(limits[:max_bytes])]}

      {false, :finished} ->
        {:ok, IO.iodata_to_binary([acc | chunks])}

      {false, :continue} ->
        inflate_chunks(z, :zlib.safeInflate(z, []), limits, new_total, [acc | chunks])
    end
  end

  # The tar stream holds each member's bytes plus its header blocks, so it may be `max_bytes` plus
  # a few blocks for each entry and the end-of-archive record.
  defp tar_size_limit(limits),
    do: limits[:max_bytes] + limits[:max_entries] * @tar_entry_overhead + @tar_end_overhead

  # Read the table first and refuse the whole archive, before anything is written, when a member
  # would escape the extraction dir (tar-slip), is not a plain file or directory, or when the
  # archive holds too many members or would unpack past the byte limit. The sizes are the ones
  # `:erl_tar.extract/2` writes (a sparse member reports its full size).
  defp safe_tar_members(tar, limits) do
    case :erl_tar.table({:binary, tar}, [:verbose]) do
      {:ok, members} ->
        check_members(members, limits)

      error ->
        {:error, [extract_error("Could not read the archive table.", error)]}
    end
  end

  defp check_members(members, limits) do
    with :ok <- within_entries(length(members), limits[:max_entries]),
         :ok <- only_files_and_dirs(members),
         :ok <- inside_extract_dir(members) do
      members
      |> Enum.reduce(0, fn {_name, _type, size, _mtime, _mode, _uid, _gid}, acc -> acc + size end)
      |> within_bytes(limits[:max_bytes])
    end
  end

  defp within_entries(count, max) when count > max do
    message = "The archive holds more than #{max} files, the most an extension may unpack."
    {:error, [extract_error(message, {:too_many_entries, count, max})]}
  end

  defp within_entries(_count, _max), do: :ok

  defp within_bytes(total, max) when total > max, do: {:error, [too_big_error(max)]}
  defp within_bytes(_total, _max), do: :ok

  defp only_files_and_dirs(members) do
    case Enum.find(members, &(elem(&1, 1) not in [:regular, :directory])) do
      nil ->
        :ok

      {name, type, _size, _mtime, _mode, _uid, _gid} ->
        message =
          "The archive holds a link or a special file; an extension may hold only regular files and directories."

        {:error, [extract_error(message, {:unsupported_member, type, to_string(name)})]}
    end
  end

  defp inside_extract_dir(members) do
    if Enum.all?(members, &safe_member?(elem(&1, 0))) do
      :ok
    else
      message = "The archive contains unsafe member paths (absolute or `..` traversal)."
      {:error, [%{message: message, field: :path, action: :extract}]}
    end
  end

  defp safe_member?(name) do
    parts = name |> to_string() |> Path.split()
    not (String.starts_with?(to_string(name), "/") or ".." in parts)
  end

  defp too_big_error(max) do
    message = "The archive would unpack past #{max} bytes, the most an extension may take."
    extract_error(message, {:too_big, max})
  end

  defp extract_error(message, source),
    do: %{message: message, field: :path, action: :extract, source: source}

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
    with {:ok, new_version} <- parse_version(version, :version),
         {:ok, installed_version} <- installed_version(app) do
      newer_than_installed(new_version, installed_version)
    end
  end

  defp installed_version(app) do
    case Application.spec(app, :vsn) do
      nil -> {:ok, nil}
      installed -> parse_version(installed, :app)
    end
  end

  defp newer_than_installed(_new_version, nil), do: :ok

  defp newer_than_installed(new_version, installed_version) do
    case Version.compare(new_version, installed_version) do
      :gt ->
        :ok

      _ ->
        message =
          "In the path of installed apps, there is an app of the same name with the same or higher version."

        {:error, [%{message: message, field: :app, action: :compare_version_with_installed_app}]}
    end
  end

  # `field` is `:version` for the version being installed and `:app` for the one already loaded.
  defp parse_version(version, field) do
    with string when is_binary(string) <- version_string(version),
         {:ok, parsed} <- Version.parse(string) do
      {:ok, parsed}
    else
      _ -> {:error, [invalid_version_error(field)]}
    end
  end

  defp version_string(version) when is_binary(version), do: version

  defp version_string(version) when is_list(version) do
    if List.ascii_printable?(version), do: List.to_string(version), else: :error
  end

  defp version_string(_version), do: :error

  defp invalid_version_error(:version) do
    message = "The version you sent is not a semantic version (expected MAJOR.MINOR.PATCH)."
    %{message: message, field: :version, action: :compare_version_with_installed_app}
  end

  defp invalid_version_error(:app) do
    message =
      "The version of the installed app of the same name is not a semantic version, so it cannot be compared."

    %{message: message, field: :app, action: :compare_version_with_installed_app}
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
