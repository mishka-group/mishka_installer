defmodule MishkaInstaller.Helper.Downloader do
  @moduledoc """
  You can find some utility functions in this module which help you to download dependencies from Hex and GitHub.
  """
  alias MishkaInstaller.Helper.Sender
  @request_name DownloaderClientApi

  # TODO: download file from github

  # TODO: unziper into RunTimeSourcing module

  # MishkaInstaller.Helper.Sender.package("hex", %{"app" => "req"})

  # https://hex.pm/api/packages/req/releases/0.1.0

  # https://api.github.com/repos/mishka-group/mishka_installer/zipball/0.0.3

  # https://api.github.com/repos/mishka-group/mishka_installer/tarball/0.0.3

  # https://stackoverflow.com/questions/30267943/elixir-download-a-file-image-from-a-url

  def test() do
    # download(:hex, "req", "0.2.2")
    # select_github_release("https://github.com/mishka-group/mishka_installer", "latest")
    # select_github_release("https://github.com/mishka-group/mishka_installer", "0.0.3")
    download(:github, "https://github.com/mishka-group/mishka_installer", "0.0.3")
  end

  def download(:hex, app, version) do
    with {:ok, :package, %{"releases" => releases} = _data} <-
           MishkaInstaller.Helper.Sender.package("hex", %{"app" => app}),
         {:ok, :select_hex_release, release_info} <- select_hex_release(releases, version),
         {:ok, :get_hex_releas_data, app_info} <- get_hex_releas_data(release_info),
         {:ok, :download_tar_from_hex, downloaded_app_body} <-
           download_tar_from_hex(app, app_info["version"]),
         {:ok, :file_write} <- file_write(app, app_info["version"], downloaded_app_body),
         {:ok, :checksum?} <- checksum?(app, app_info) do
      {:ok, :download, :hex, app_info}
    end
  end

  def download(:github, url, version) do
    with {:ok, :select_github_release, app_name, version, tar_url} <- select_github_release(url, version),
         {:ok, :download_tar_from_github, downloaded_app_body} <- download_tar_from_github(tar_url),
         {:ok, :file_write} <- file_write("#{app_name}", version, downloaded_app_body)  do

      {:ok, :download, :github, %{"app" => "#{app_name}", "version" => version}}
    end
  end

  # erl_tar:extract("rel/project-1.0.tar.gz", [compressed]);
  def extract(:tar, archived_file, extracted_name) do
    :erl_tar.extract(
      ~c'#{extensions_path()}/#{archived_file}.tar',
      [
        {:cwd, ~c'#{extensions_path()}/#{extracted_name}'}
      ]
    )
  end

  def extract(:zip, archived_file, extracted_name) do
    :zip.unzip(
      ~c'#{extensions_path()}/#{archived_file}.zip',
      [
        {:cwd, ~c'#{extensions_path()}/#{extracted_name}'}
      ]
    )
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
    with {:error, posix} <-
           File.write("#{extensions_path()}/#{app}-#{version}.tar", downloaded_app_body) do
      {:error, :file_write, {:error, posix}}
    else
      _ -> {:ok, :file_write}
    end
  end

  defp checksum?(app, app_info) do
    (MishkaInstaller.checksum("#{extensions_path()}/#{app}-#{app_info["version"]}.tar") ==
       app_info["checksum"])
    |> case do
      false -> {:error, :checksum?, :unequal}
      true -> {:ok, :checksum?}
    end
  end

  defp select_github_release(url, "latest") do
    case MishkaInstaller.Helper.Sender.package("github_latest_release", url) do
      {:ok, :package, %{"tag_name" => version}} -> select_github_release(url, version)
      _ -> {:error, :select_github_release, :not_found}
    end
  end

  defp select_github_release(url, version) do
    case Sender.package("github", %{"url" => url, "tag" => version}) do
      {:error, :package, :not_found} ->
        {:error, :select_github_release, :not_found}

      data ->
        {:ok, :select_github_release, data[:app], data[:version],
         "#{String.replace(String.trim(url), "https://github.com/", "https://codeload.github.com/")}/legacy.tar.gz/refs/tags/#{version}"}
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
end
