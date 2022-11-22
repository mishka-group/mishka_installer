defmodule MishkaInstaller.Helper.LibraryMaker do
  @moduledoc """
  You can find some utility functions in this module which help you to download dependencies from Hex and GitHub and prepare them as library.

  # TODO: unziper into RunTimeSourcing module

  ### Testing resource
  - MishkaInstaller.Helper.Sender.package("hex", %{"app" => "req"})
  - https://hex.pm/api/packages/req/releases/0.1.0
  - https://api.github.com/repos/mishka-group/mishka_installer/tarball/0.0.3
  - https://stackoverflow.com/questions/30267943/elixir-download-a-file-image-from-a-url
  """
  alias MishkaInstaller.Helper.Sender
  @request_name DownloaderClientApi

  @spec run(:github | :hex, String.t(), String.t()) ::
          list | {:error, atom(), atom} | {:ok, :run, binary}
  def run(type, app, version) do
    with {:ok, :download, _, app_info, pkg} <- download(type, app, version),
         file_path <- "#{extensions_path()}/#{app_info["app"]}-#{app_info["version"]}",
         {:ok, :extract} <- extract(:tar, "#{app_info["app"]}-#{app_info["version"]}"),
         {:ok, files} <-
           File.ls("#{extensions_path()}/#{app_info["app"]}-#{app_info["version"]}"),
         extracted_file_type <- Enum.member?(files, "contents.tar.gz"),
         _final_lib_path <-
           extracted_to_normal_project(app_info, file_path, files, extracted_file_type) do
      {:ok, :package, pkg}
    end
  end

  @doc """
  A function which download a package from Hex/Github and save it in the `deployment/extensions` folder.
  """
  @spec download(:github | :hex, String.t(), String.t()) ::
          list | {:error, atom(), atom} | {:ok, :download, :github | :hex, map(), map | list()}
  def download(:hex, app, version) do
    with {:ok, :package, %{"releases" => releases} = pkg} <-
           MishkaInstaller.Helper.Sender.package("hex", %{"app" => app}),
         {:ok, :select_hex_release, release_info} <- select_hex_release(releases, version),
         {:ok, :get_hex_releas_data, app_info} <- get_hex_releas_data(release_info),
         {:ok, :download_tar_from_hex, downloaded_app_body} <-
           download_tar_from_hex(app, app_info["version"]),
         {:ok, :file_write} <- file_write(app, app_info["version"], downloaded_app_body),
         {:ok, :checksum?} <- checksum?(app, app_info) do
      {:ok, :download, :hex, %{"app" => "#{app}", "version" => app_info["version"]}, pkg}
    else
      {:error, _section, result} -> {:error, :package, result}
    end
  rescue
    _e in Protocol.UndefinedError ->
      {:error, :package, :invalid_version}

    _ ->
      {:error, :package, :unhandled}
  end

  def download(:github, url, version) do
    with {:ok, :select_github_release, pkg, tar_url} <-
           select_github_release(url, version),
         {:ok, :download_tar_from_github, downloaded_app_body} <-
           download_tar_from_github(tar_url),
         {:ok, :file_write} <- file_write("#{pkg[:app]}", pkg[:version], downloaded_app_body) do
      {:ok, :download, :github, %{"app" => "#{pkg[:app]}", "version" => pkg[:version]}, pkg}
    else
      {:error, _section, result} -> {:error, :package, result}
    end
  rescue
    _e in Protocol.UndefinedError ->
      {:error, :package, :invalid_version}

    _ ->
      {:error, :package, :unhandled}
  end

  # erl_tar:extract("rel/project-1.0.tar.gz", [compressed]);
  @spec extract(:tar, String.t()) :: {:error, :extract} | {:ok, :extract}
  def extract(:tar, archived_file) do
    extract_output =
      :erl_tar.extract(
        ~c'#{extensions_path()}/#{archived_file}.tar.gz',
        [:compressed, {:cwd, ~c'#{extensions_path()}/#{archived_file}'}]
      )

    case extract_output do
      :ok -> {:ok, :extract}
      {:error, term} -> {:error, :extract, term}
    end
  end

  @spec change_uploaded_file(String.t(), String.t()) :: [binary]
  def change_uploaded_file(file_path, app_name) do
    new_lib_path =
      Path.join(MishkaInstaller.get_config(:project_path), [
        "deployment/",
        "extensions/#{app_name}"
      ])

    String.replace(file_path, Path.extname(file_path), "")
    |> File.rename(new_lib_path)

    File.rm_rf!(file_path)
  end

  defp get_hex_releas_data(app_info) do
    Finch.build(:get, app_info["url"])
    |> Finch.request(@request_name)
    |> case do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, :get_hex_releas_data, Jason.decode!(body)}

      _ ->
        {:error, :get_hex_releas_data, :not_found}
    end
  end

  defp select_hex_release(releases, "latest") when length(releases) > 0,
    do: {:ok, :select_hex_release, List.first(releases)}

  defp select_hex_release(releases, version) when length(releases) > 0 do
    releases
    |> Enum.find(&(&1["version"] == version))
    |> case do
      nil -> {:error, :select_hex_release, :not_found}
      data -> {:ok, :select_hex_release, data}
    end
  end

  defp select_hex_release(_releases, _version), do: {:error, :select_hex_release, :not_found}

  defp download_tar_from_hex(app, version) do
    Finch.build(:get, "https://repo.hex.pm/tarballs/#{app}-#{version}.tar")
    |> Finch.request(@request_name)
    |> case do
      {:ok, %Finch.Response{status: 200, body: body}} -> {:ok, :download_tar_from_hex, body}
      _ -> {:error, :download_tar_from_hex, :not_found}
    end
  end

  defp extensions_path() do
    Path.join(MishkaInstaller.get_config(:project_path), ["deployment/", "extensions"])
  end

  defp file_write(app, version, downloaded_app_body) do
    case File.write("#{extensions_path()}/#{app}-#{version}.tar.gz", downloaded_app_body) do
      {:error, posix} -> {:error, :file_write, posix}
      _ -> {:ok, :file_write}
    end
  end

  defp checksum?(app, app_info) do
    (MishkaInstaller.checksum("#{extensions_path()}/#{app}-#{app_info["version"]}.tar.gz") ==
       app_info["checksum"])
    |> case do
      false -> {:error, :checksum?, :unequal}
      true -> {:ok, :checksum?}
    end
  end

  # - https://elixirforum.com/t/how-to-download-a-file-with-finch-which-is-redirected/50368
  defp select_github_release(url, "latest") do
    case Sender.package("github_latest_release", url) do
      {:ok, :package, %{"tag_name" => version}} -> select_github_release(url, version)
      _ -> {:error, :select_github_release, :not_found}
    end
  end

  defp select_github_release(url, version) do
    case Sender.package("github", %{"url" => url, "tag" => version}) do
      {:error, :package, :not_found} ->
        {:error, :select_github_release, :not_found}

      data ->
        {:ok, :select_github_release, data,
         "#{String.replace(MishkaInstaller.trim_url(url), "https://github.com/", "https://codeload.github.com/")}/legacy.tar.gz/refs/tags/#{version}"}
    end
  end

  defp download_tar_from_github(url) do
    Finch.build(:get, url)
    |> Finch.request(@request_name)
    |> case do
      {:ok, %Finch.Response{status: 200, body: body}} -> {:ok, :download_tar_from_github, body}
      _ -> {:error, :download_tar_from_github, :not_found}
    end
  end

  defp extracted_to_normal_project(app_info, lib_path, files, true) do
    File.rm_rf!(Path.join(extensions_path(), ["#{app_info["app"]}"]))
    Enum.map(files, &if(&1 != "contents.tar.gz", do: File.rm_rf!("#{lib_path}/#{&1}")))
    :erl_tar.extract(~c'#{lib_path}/contents.tar.gz', [:compressed, {:cwd, ~c'#{lib_path}'}])

    ["#{lib_path}/contents.tar.gz", "#{lib_path}.tar.gz"]
    |> Enum.map(&File.rm_rf!(&1))

    File.rename(lib_path, Path.join(extensions_path(), ["#{app_info["app"]}"]))
    Path.join(extensions_path(), ["#{app_info["app"]}"])
  end

  defp extracted_to_normal_project(app_info, lib_path, files, false) do
    File.rm_rf!(Path.join(extensions_path(), ["#{app_info["app"]}"]))
    Enum.map(files, &if(!File.dir?("#{lib_path}/#{&1}"), do: File.rm_rf!("#{lib_path}/#{&1}")))

    nested_dir =
      File.ls!("#{extensions_path()}/#{app_info["app"]}-#{app_info["version"]}") |> List.first()

    File.cp_r!(
      Path.join(lib_path, ["#{nested_dir}"]),
      Path.join(extensions_path(), ["#{app_info["app"]}"])
    )

    [lib_path, "#{lib_path}.tar.gz"]
    |> Enum.map(&File.rm_rf!(&1))

    Path.join(extensions_path(), ["#{app_info["app"]}-#{app_info["version"]}."])
  end
end
