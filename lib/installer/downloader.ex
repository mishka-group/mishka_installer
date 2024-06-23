defmodule MishkaInstaller.Installer.Downloader do
  @moduledoc """
  The `MishkaInstaller.Installer.Downloader` module provides functions for downloading packages
  from various sources such as `Hex.pm` and `GitHub`.

  It supports different download types and can fetch specific **versions** or the **latest releases**.
  This module also includes functions for retrieving `mix.exs` files from these sources.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  """
  @hex_path "https://hex.pm/api/packages"
  @hex_preview_path "https://repo.hex.pm/preview"
  @github_path "https://raw.githubusercontent.com"
  @github_api_path "https://api.github.com/repos"
  @github_codeload_path "https://codeload.github.com"

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

  @type okey_return :: {:ok, struct() | map() | binary()}

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @doc """
  Downloads a package from the specified source.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ### Example:
  ```elixir
  download(:hex, %{app: app, tag: tag_name})
  download(:github, %{path: path, branch: {branch, git: true}})
  download(:github, %{path: path, branch: branch})
  download(:github, %{path: path, release: release})
  download(:github, %{path: path, tag: tag})
  download(:hex, %{app: app})
  download(:github, %{path: path})
  download(:github_latest_release, %{path: path})
  download(:github_latest_tag, %{path: path})
  ```
  """
  @spec download(download_type, pkg) :: okey_return | error_return
  def download(:hex, %{app: app, tag: tag_name}) when not is_nil(tag_name) do
    case build_url("https://repo.hex.pm/tarballs/#{app}-#{tag_name}.tar") do
      %Req.Response{status: 200, body: body} ->
        converted = Map.new(body, fn {key, value} -> {to_string(key), value} end)
        {:ok, converted["contents.tar.gz"]}

      _ ->
        mix_global_err()
    end
  end

  def download(:github, %{path: path, branch: {branch, git: true}}) do
    case build_url(
           "#{@github_codeload_path}/#{String.trim(path)}/legacy.tar.gz/refs/heads/#{branch}"
         ) do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, branch: branch}) when not is_nil(branch) do
    case build_url("https://github.com/#{String.trim(path)}/archive/refs/heads/#{branch}.tar.gz") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, release: release}) when not is_nil(release) do
    case build_url("https://github.com/#{String.trim(path)}/archive/refs/tags/#{release}.tar.gz") do
      %Req.Response{status: 200, body: body} -> {:ok, body}
      _ -> mix_global_err()
    end
  end

  def download(:github, %{path: path, tag: tag}) when not is_nil(tag) do
    case build_url("https://github.com/#{String.trim(path)}/archive/refs/tags/#{tag}.tar.gz") do
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
    case build_url("#{@github_api_path}/#{String.trim(path)}") do
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

  def download(:url, %{path: path}) do
    case build_url(path) do
      %Req.Response{status: 200, body: body} -> body
      _ -> mix_global_err()
    end
  end

  def download(_, _) do
    message = "The information sent to download the desired library is wrong!"
    {:error, [%{message: message, field: :path, action: :download}]}
  end

  @doc """
  Retrieves the `mix.exs` file for the specified package.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ### Example:
  ```elixir
  get_mix(:hex, %{app: app, tag: tag_name})
  get_mix(:github_release, %{path: path, release: tag_name})
  get_mix(:github_tag, %{path: path, tag: tag_name})
  get_mix(:hex, %{app: app})
  get_mix(:github, %{path: path})
  get_mix(:github_latest_release, %{path: path})
  get_mix(:github_latest_tag, %{path: path})
  get_mix(:url, %{path: path})
  ```
  """
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

      _e ->
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
    message = msg || "There is a problem downloading the mix.exs/project."
    {:error, [%{message: message, field: :path, action: :download}]}
  end

  # Based on https://hexdocs.pm/req/Req.Test.html#module-example
  defp build_url(location) do
    [base_url: location]
    |> Keyword.merge(Application.get_env(:mishka_installer, :downloader_req_options, []))
    |> Keyword.merge(Application.get_env(:mishka_installer, :proxy, []))
    |> Req.request!()
  end
end
