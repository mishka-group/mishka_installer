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

  > #### Security considerations {: .warning}
  >
  > It is important to remember that all of the functionalities contained within this
  > section must be implemented at the **high access level**, and they should not directly take
  > any input from the user. Ensure that you include the required safety measures.
  >
  > A downloaded artifact is loaded as code with full node privileges; only download from trusted
  > sources and verify its provenance/integrity before activation.
  """
  @github_api_path "https://api.github.com/repos"

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
  def download(:url, %{path: path}) do
    # `raw: true` disables Req's body decompression + decoding so we get the exact on-wire bytes
    # of the `tar.gz` artifact (some CDNs set `content-encoding: gzip`, which Req would otherwise
    # transparently decompress and break `:erl_tar` extraction).
    case build_url(path, raw: true) do
      %Req.Response{status: 200, body: body} when is_binary(body) -> {:ok, body}
      _ -> download_err()
    end
  end

  def download(:github_tag, %{path: path, tag: tag} = pkg) when not is_nil(tag) do
    release_asset("#{@github_api_path}/#{String.trim(path)}/releases/tags/#{tag}", pkg)
  end

  def download(:github_latest_release, %{path: path} = pkg) do
    release_asset("#{@github_api_path}/#{String.trim(path)}/releases/latest", pkg)
  end

  def download(_, _) do
    download_err("The information sent to download the desired library is wrong!")
  end

  ####################################################################################
  ########################## (▰˘◡˘▰) Helper (▰˘◡˘▰) ############################
  ####################################################################################
  # Resolve the asset's download URL from a GitHub release payload, then download it.
  defp release_asset(api_url, pkg) do
    case build_url(api_url) do
      %Req.Response{status: 200, body: %{"assets" => assets}} when is_list(assets) ->
        case pick_asset(assets, Map.get(pkg, :asset)) do
          nil -> download_err("No matching release asset was found.")
          asset_url -> download(:url, %{path: asset_url})
        end

      _ ->
        download_err()
    end
  end

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

  # Based on https://hexdocs.pm/req/Req.Test.html#module-example
  defp build_url(location, args \\ []) do
    [base_url: location]
    |> Keyword.merge(args)
    |> Keyword.merge(Application.get_env(:mishka_installer, :downloader_req_options, []))
    |> Keyword.merge(Application.get_env(:mishka_installer, :proxy, []))
    |> Req.request!()
  end
end
