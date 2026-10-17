defmodule MishkaInstaller.Installer.Downloader do
  @moduledoc """
  The `MishkaInstaller.Installer.Downloader` module downloads a **pre-built artifact** — a `tar.gz`
  that contains a compiled `ebin` directory (`ebin/*.beam` + `ebin/<app>.app`).

  > It deliberately does **not** download source to be compiled at runtime. Compiling cannot work
  > in a production `release` (no `Mix`/`Hex`/source/`_build`), so the publisher is expected to
  > attach the **already compiled** artifact (typically a **GitHub release** asset, a CDN, or any URL).

  Supported sources:

  - `:url` — a direct artifact URL (a GitHub release asset URL, an S3/CDN link, ...).
  - `:github_tag` — resolve the asset of a specific release **tag** via the GitHub API.
  - `:github_latest_release` — resolve the asset of the **latest** release via the GitHub API.

  ## GitHub

  For `:github_tag` and `:github_latest_release`, `path` must be `"owner/repo"` and `tag` and `asset`
  may only contain letters, digits and `. _ + -`; anything else is an `{:error, ...}` before a request
  is made. The asset must be an `https` URL on `github.com`.

  ## Scheme

  Only `https` URLs are downloaded. Any other scheme (`http`, `file`, none) is an `{:error, ...}`
  and nothing is requested.

  ## Redirects

  A redirect is followed by hand, at most 3 times. Every hop must be `https` and its host must be
  the host of the first URL, a host of `config :mishka_installer, :allowlist, url_hosts: [...]`, or,
  when the first URL is on `github.com`/`api.github.com`, GitHub's release CDN
  (`release-assets.githubusercontent.com`, `objects.githubusercontent.com`). Any other hop is an
  `{:error, ...}` and nothing is downloaded from it.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > A downloaded artifact is loaded as code with full node privileges; only download from trusted
  > sources and verify its provenance/integrity before activation.
  """
  require Logger

  @github_api_path "https://api.github.com/repos"
  @github_hosts ["github.com", "api.github.com"]
  @github_release_hosts ["release-assets.githubusercontent.com", "objects.githubusercontent.com"]
  @max_redirects 3
  @redirect_statuses [301, 302, 303, 307, 308]
  @github_name ~r/\A[A-Za-z0-9._+-]+\z/
  @github_repo ~r/\A[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+\z/

  @type download_type :: :url | :github_tag | :github_latest_release

  @type pkg ::
          %{path: String.t()}
          | %{path: String.t(), tag: String.t()}
          | %{path: String.t(), asset: String.t()}

  @type error_return :: {:error, [%{action: atom(), field: atom(), message: String.t()}]}

  @type okey_return :: {:ok, binary()}

  ####################################################################################
  ######################### (▰˘◡˘▰) Functions (▰˘◡˘▰) ##########################
  ####################################################################################
  @doc """
  Downloads a pre-built artifact (a `tar.gz` containing the compiled `ebin`) from the given source.

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.

  ### Example:
  ```elixir
  download(:url, %{path: "https://github.com/owner/repo/releases/download/0.1.0/app-0.1.0-ebin.tar.gz"})
  download(:github_tag, %{path: "owner/repo", tag: "0.1.0"})
  download(:github_tag, %{path: "owner/repo", tag: "0.1.0", asset: "app-ebin.tar.gz"})
  download(:github_latest_release, %{path: "owner/repo"})
  ```
  """
  @spec download(download_type, pkg) :: okey_return | error_return
  def download(:url, %{path: path}) when is_binary(path) do
    case URI.parse(path) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        # `raw: true` disables Req's body decompression + decoding so we get the exact on-wire bytes
        # of the `tar.gz` artifact (some CDNs set `content-encoding: gzip`, which Req would otherwise
        # transparently decompress and break `:erl_tar` extraction).
        case fetch(path, redirect_hosts(path), @max_redirects, raw: true) do
          {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> {:ok, body}
          {:ok, _response} -> download_err()
          {:error, _reason} = error -> error
        end

      _ ->
        download_err("Only https URLs can be downloaded.")
    end
  end

  def download(:github_tag, %{path: path, tag: tag} = pkg) when not is_nil(tag) do
    with {:ok, repo} <- github_repo(path),
         :ok <- github_name(tag),
         :ok <- github_name(Map.get(pkg, :asset)) do
      release_asset("#{@github_api_path}/#{repo}/releases/tags/#{tag}", pkg)
    end
  end

  def download(:github_latest_release, %{path: path} = pkg) do
    with {:ok, repo} <- github_repo(path),
         :ok <- github_name(Map.get(pkg, :asset)) do
      release_asset("#{@github_api_path}/#{repo}/releases/latest", pkg)
    end
  end

  def download(_, _) do
    download_err("The information sent to download the desired library is wrong!")
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  # `path` must be "owner/repo" and `tag`/`asset` a plain name: they are put into the API URL as they are.
  defp github_repo(path) when is_binary(path) do
    repo = String.trim(path)

    if Regex.match?(@github_repo, repo) and not Enum.any?(String.split(repo, "/"), &dots_only?/1),
      do: {:ok, repo},
      else: github_input_err()
  end

  defp github_repo(_path), do: github_input_err()

  defp github_name(nil), do: :ok

  defp github_name(name) when is_binary(name) do
    if Regex.match?(@github_name, name) and not dots_only?(name),
      do: :ok,
      else: github_input_err()
  end

  defp github_name(_name), do: github_input_err()

  defp dots_only?(segment), do: segment in [".", ".."]

  defp github_input_err do
    download_err(
      "The GitHub repository must be \"owner/repo\", and the tag and asset names may only " <>
        "contain letters, digits and . _ + -"
    )
  end

  # Resolve the asset's download URL from a GitHub release payload, then download it.
  defp release_asset(api_url, pkg) do
    case fetch(api_url, redirect_hosts(api_url), @max_redirects, []) do
      {:ok, %Req.Response{status: 200, body: %{"assets" => assets}}} when is_list(assets) ->
        case pick_asset(assets, Map.get(pkg, :asset)) do
          nil -> download_err("No matching release asset was found.")
          asset_url -> download_github_asset(asset_url)
        end

      {:error, _reason} = error ->
        error

      _ ->
        download_err()
    end
  end

  defp download_github_asset(asset_url) when is_binary(asset_url) do
    case URI.parse(asset_url) do
      %URI{scheme: "https", host: "github.com"} -> download(:url, %{path: asset_url})
      _ -> download_err("The release asset is not an https URL on github.com.")
    end
  end

  defp download_github_asset(_asset_url), do: download_err("No matching release asset was found.")

  defp pick_asset([], _name), do: nil
  defp pick_asset([asset | _], nil), do: asset["browser_download_url"]

  defp pick_asset(assets, name) do
    case Enum.find(assets, &(&1["name"] == name)) do
      nil -> nil
      asset -> asset["browser_download_url"]
    end
  end

  defp download_err(msg \\ nil) do
    message = msg || "There is a problem downloading the pre-built artifact."
    {:error, [%{message: message, field: :path, action: :download}]}
  end

  # Redirects are never followed by Req: each `Location` is checked against `hosts` and followed here.
  defp fetch(url, hosts, hops_left, args) do
    case build_url(url, Keyword.put(args, :redirect, false)) do
      {:ok, %Req.Response{status: status} = response} when status in @redirect_statuses ->
        follow(response, url, hosts, hops_left, args)

      {:ok, response} ->
        {:ok, response}

      {:error, exception} ->
        Logger.warning(
          "[mishka_installer.downloader] request to #{inspect(URI.parse(url).host)} failed: " <>
            Exception.message(exception)
        )

        download_err()
    end
  end

  defp follow(_response, _url, _hosts, 0, _args) do
    download_err("The download redirected too many times.")
  end

  defp follow(response, url, hosts, hops_left, args) do
    with [location | _] <- Req.Response.get_header(response, "location"),
         %URI{scheme: "https", host: host} = next when is_binary(host) <-
           URI.merge(URI.parse(url), location),
         true <- normalize_host(host) in hosts do
      fetch(URI.to_string(next), hosts, hops_left - 1, args)
    else
      _ -> download_err("The download redirected to a location that is not allowed.")
    end
  end

  defp redirect_hosts(url) do
    origin = normalize_host(URI.parse(url).host)

    configured =
      :mishka_installer
      |> Application.get_env(:allowlist, [])
      |> Keyword.get(:url_hosts, [])
      |> Enum.map(&normalize_host/1)

    github = if origin in @github_hosts, do: @github_release_hosts, else: []

    Enum.uniq([origin | configured] ++ github)
  end

  defp normalize_host(nil), do: nil
  defp normalize_host(host), do: host |> to_string() |> String.downcase()

  # Based on https://hexdocs.pm/req/Req.Test.html#module-example
  defp build_url(location, args) do
    [base_url: location]
    |> Keyword.merge(args)
    |> Keyword.merge(Application.get_env(:mishka_installer, :downloader_req_options, []))
    |> Keyword.merge(Application.get_env(:mishka_installer, :proxy, []))
    |> Req.request()
  end
end
