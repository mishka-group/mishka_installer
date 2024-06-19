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
          | %{path: String.t(), branch: String.t() | tuple()}

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, struct() | map()}

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @spec download(download_type, pkg) :: okey_return | error_return
  def download(:hex, %{app: app, tag: tag_name}) do
    case build_url("https://repo.hex.pm/tarballs/#{app}-#{tag_name}.tar") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, branch: {branch, git: true}}) do
    case build_url("https://codeload.github.com/#{path}/legacy.tar.gz/refs/heads/#{branch}") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, branch: branch}) do
    case build_url("https://github.com/#{path}/archive/refs/heads/#{branch}.tar.gz") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, release: release}) do
    case build_url("https://github.com/#{path}/archive/refs/tags/#{release}.tar.gz") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, tag: tag}) do
    case build_url("https://github.com/#{path}/archive/refs/tags/#{tag}.tar.gz") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:hex, %{app: app}) do
    case build_url("#{@hex_path}/#{String.trim(app)}") do
      %Req.Response{status: 200, body: %{"latest_stable_version" => tag_name}} ->
        download(:hex, %{app: app, tag: tag_name})

      _ ->
        mix_global_err()
    end
  end

  def download(:github, %{path: path}) do
    case build_url("#{@github_api_path}/#{path}") do
      %Req.Response{status: 200, body: %{"default_branch" => branch_name}} ->
        download(:github, %{path: path, branch: branch_name})

      _ ->
        mix_global_err()
    end
  end

  def download(:github_latest_release, %{path: path}) do
    case build_url("#{@github_api_path}/#{String.trim(path)}/releases/latest") do
      %Req.Response{status: 200, body: %{"tag_name" => tag_name}} ->
        download(:github, %{path: path, release: tag_name})

      _ ->
        mix_global_err()
    end
  end

  def download(:github_latest_tag, %{path: path}) do
    case build_url("#{@github_api_path}/#{String.trim(path)}/tags") do
      %Req.Response{status: 200, body: body} when body != [] ->
        if is_nil(List.first(body)) do
          mix_global_err("No tags found.")
        else
          download(:github, %{path: path, tag: List.first(body)["name"]})
        end

      _ ->
        mix_global_err()
    end
  end

  # ************************************************************
  # ************************************************************
  # ************************************************************
  @spec get_mix(download_type, pkg) :: okey_return | error_return
  def get_mix(:hex, %{app: app, tag: tag_name}) do
    get_mix(:url, %{path: "#{@hex_preview_path}/#{app}/#{tag_name}/mix.exs"})
  end

  def get_mix(:github_release, %{path: path, release: tag_name}) do
    get_mix(:github_tag, %{path: path, tag: tag_name})
  end

  def get_mix(:github_tag, %{path: path, tag: tag_name}) do
    case build_url("#{@github_path}/#{String.trim(path)}/#{tag_name}/mix.exs") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def get_mix(:hex, %{app: app}) do
    case build_url("#{@hex_path}/#{String.trim(app)}") do
      %Req.Response{status: 200, body: %{"latest_stable_version" => tag_name}} ->
        get_mix(:hex, %{app: app, tag: tag_name})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:github, %{path: path}) do
    case build_url("#{@github_api_path}/#{String.trim(path)}/contents/mix.exs") do
      %Req.Response{status: 200, body: %{"download_url" => url}} ->
        get_mix(:url, %{path: url})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:github_latest_release, %{path: path}) do
    case build_url("#{@github_api_path}/#{String.trim(path)}/releases/latest") do
      %Req.Response{status: 200, body: %{"tag_name" => tag_name}} ->
        get_mix(:github_tag, %{path: path, tag: tag_name})

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:github_latest_tag, %{path: path}) do
    case build_url("#{@github_api_path}/#{String.trim(path)}/tags") do
      %Req.Response{status: 200, body: body} when body != [] ->
        if is_nil(List.first(body)) do
          mix_global_err("No tags found.")
        else
          get_mix(:github_tag, %{path: path, tag: List.first(body)["name"]})
        end

      _ ->
        mix_global_err()
    end
  end

  def get_mix(:url, %{path: path}) do
    case build_url(path) do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  defp mix_global_err(msg \\ nil) do
    message = msg || "There is a problem downloading the mix.exs file."
    {:error, [%{message: message, field: :path, action: :package}]}
  end

  # Based on https://hexdocs.pm/req/Req.Test.html#module-example
  defp build_url(location) do
    [base_url: location]
    |> Keyword.merge(Application.get_env(:mishka_installer, :downloader_req_options, []))
    |> Req.request!()
  end
end
