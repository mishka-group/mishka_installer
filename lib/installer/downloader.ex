defmodule MishkaInstaller.Installer.Downloader do
  @hex_path "https://hex.pm/api/packages"
  @hex_preview_path "https://repo.hex.pm/preview"
  @github_path "https://raw.githubusercontent.com"
  @github_api_path "https://api.github.com/repos"

  @type download_type ::
          :hex
          | :github
          | :github_latest_release
          | :github_latest_tag
          | :github_release
          | :github_tag
          | :url

  @type pkg ::
          %{app: String.t()}
          | %{app: String.t(), tag: String.t()}
          | %{path: String.t()}
          | %{path: String.t(), release: String.t()}
          | %{path: String.t(), tag: String.t()}

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map()}

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec get_mix(download_type, pkg) :: okey_return | error_return
  def get_mix(:hex, %{app: app, tag: tag_name}) do
    get_mix(:url, %{path: "#{@hex_preview_path}/#{app}/#{tag_name}/mix.exs"})
  end

  def get_mix(:github_release, %{path: path, release: tag_name}) do
    get_mix(:github_tag, %{path: path, tag: tag_name})
  end

  def get_mix(:github_tag, %{path: path, tag: tag_name}) do
    case Req.get!("#{@github_path}/#{String.trim(path)}/#{tag_name}/mix.exs") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def get_mix(:hex, %{app: app}) do
    case Req.get!("#{@hex_path}/#{String.trim(app)}") do
      %Req.Response{status: 200, body: %{"latest_stable_version" => tag_name}} ->
        get_mix(:hex, %{app: app, tag: tag_name})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:github, %{path: path}) do
    case Req.get!("#{@github_api_path}/#{String.trim(path)}/contents/mix.exs") do
      %Req.Response{status: 200, body: %{"download_url" => url}} ->
        get_mix(:url, %{path: url})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:github_latest_release, %{path: path}) do
    case Req.get!("#{@github_api_path}/#{String.trim(path)}/releases/latest") do
      %Req.Response{status: 200, body: %{"tag_name" => tag_name}} ->
        get_mix(:github_tag, %{path: path, tag: tag_name})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:github_latest_tag, %{path: path}) do
    case Req.get!("#{@github_api_path}/#{String.trim(path)}/tags") do
      %Req.Response{status: 200, body: body} when body != [] ->
        get_mix(:github_tag, %{path: path, tag: List.first(body)["name"]})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:url, %{path: path}) do
    case Req.get!(path) do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  defp mix_global_err() do
    message = "There is a problem downloading the mix.exs file."
    {:error, [%{message: message, field: :path, action: :package}]}
  end
end
