defmodule MishkaInstaller.DepUpdateJob do
  @moduledoc """
  This module provides assistance to your software so that it may check all of the plugins and libraries that you have installed
  to see whether a newer version of those extensions has been made available.
  """
  use Oban.Worker, queue: :update_events, max_attempts: 1
  require Logger
  alias MishkaInstaller.Helper.Sender
  @module "dependency_update_check"
  @ets_table :dependency_update

  @doc false
  @impl Oban.Worker
  def perform(%Oban.Job{}), do: check_added_dependencies_update()

  @doc """
  This function provides a channel to get new updates of extension releases; your project can subscribe and use this information.

  ## Examples

  ```elixir
  MishkaInstaller.DepUpdateJob.subscribe()
  ```
  """
  @spec subscribe :: :ok | {:error, {:already_registered, pid}}
  def subscribe do
    Phoenix.PubSub.subscribe(MishkaInstaller.PubSub, @module)
  end

  @doc """
  Get new release information of an extension.

  ## Examples

  ```elixir
  MishkaInstaller.DepUpdateJob.get("test_app")
  ```
  """
  @spec get(binary) :: nil | tuple
  def get(app) do
    case ETS.Set.get(ets(), String.to_atom(app)) do
      {:ok, data} -> data
      _ -> nil
    end
  end

  @doc """
  Get new releases information of extensions.

  ## Examples

  ```elixir
  MishkaInstaller.DepUpdateJob.get_all()
  ```
  """
  @spec get_all :: [tuple]
  def get_all() do
    ETS.Set.to_list!(ets())
  end

  @doc """
  Check and find new updates of extensions if new releases exist. This function just returns `:ok` atom and saves update news into ETS.

  ## Examples

  ```elixir
  MishkaInstaller.DepUpdateJob.check_added_dependencies_update()
  ```
  """
  @spec check_added_dependencies_update :: :ok
  def check_added_dependencies_update() do
    Logger.warn("DepUpdateJob request was sent")

    MishkaInstaller.Installer.DepHandler.read_dep_json()
    |> send_update_request_based_on_type()
    |> store_update_information_into_ets(ets())
    |> notify_subscribers()

    :ok
  end

  defp send_update_request_based_on_type({:ok, :read_dep_json, dependencies}),
    do: Enum.map(dependencies, &create_update_request/1)

  defp send_update_request_based_on_type(_) do
    MishkaInstaller.update_activity(%{app: "none", type: "update", status: :server_error}, "high")
    {:error, :access_json_file}
  end

  defp store_update_information_into_ets({:error, :access_json_file}, _ets_set), do: []

  defp store_update_information_into_ets(data, ets_set) do
    ETS.Set.delete_all(ets_set)

    Enum.map(data, fn
      {:ok, app_info, true} -> push(app_info, ets_set)
      _ -> nil
    end)
  end

  defp create_update_request(%{"type" => "git", "git_tag" => tag} = json_data)
       when tag in ["master", "main"] do
    case Sender.package("github", %{"url" => json_data["url"], "tag" => tag}) do
      {:error, :package, error_status} ->
        MishkaInstaller.update_activity(
          %{app: json_data["app"], type: :git, status: error_status},
          "high"
        )

        {:error, :git, json_data, error_status}

      [app: _app, version: version, source_url: _source_url, tag: _tag] ->
        {:ok, {String.to_atom(json_data["app"]), :git, json_data["url"], version},
         version_compare(version, json_data["version"], :git, json_data["app"])}
    end
  end

  defp create_update_request(%{"type" => "git", "git_tag" => _tag} = json_data) do
    Sender.package("github_latest_tag", json_data["url"])
    |> github_tag(json_data)
  end

  defp create_update_request(%{"type" => "hex"} = json_data) do
    case Sender.package("hex", %{"app" => json_data["app"]}) do
      {:ok, :package, %{"latest_stable_version" => version}} ->
        {:ok, {String.to_atom(json_data["app"]), :hex, json_data["url"], version},
         version_compare(version, json_data["version"], :hex, json_data["app"])}

      {:error, :package, error_status} ->
        MishkaInstaller.update_activity(
          %{app: json_data["app"], type: :hex, status: error_status},
          "high"
        )

        {:error, :hex, json_data, error_status}
    end
  end

  # Skip path type libraries and do not send any request for checking update
  defp create_update_request(%{"type" => "path"} = json_data) do
    {:error, {String.to_atom(json_data["app"]), :path, json_data["url"], json_data["version"]}, false}
  end

  defp github_tag({:ok, :package, []}, json_data), do: {:error, :git, json_data, :empty_tag_list}

  defp github_tag({:ok, :package, pkg}, json_data) do
    version = List.first(pkg)["name"]

    {:ok, {String.to_atom(json_data["app"]), :git, json_data["url"], version},
     version_compare(version, json_data["version"], :git, json_data["app"])}
  end

  defp github_tag({:error, :package, error_status}, json_data) do
    MishkaInstaller.update_activity(
      %{app: json_data["app"], type: :hex, status: error_status},
      "high"
    )

    {:error, :git, json_data, error_status}
  end

  defp notify_subscribers(_answer) do
    Phoenix.PubSub.broadcast(MishkaInstaller.PubSub, @module, {String.to_atom(@module)})
  end

  defp push(data, ets_set) do
    ETS.Set.put!(ets_set, data)
  end

  defp version_compare(request_ver, json_ver, type, app) do
    request_ver =
      request_ver
      |> String.replace("~>", "")
      |> String.replace(">=", "")
      |> String.replace("v", "")
      |> String.trim()

    if Version.compare(request_ver, json_ver) == :gt, do: true, else: false
  rescue
    _ ->
      MishkaInstaller.update_activity(
        %{app: app, type: type, status: :server_bad_version},
        "high"
      )

      false
  end

  @doc """
  Start ETS table to store new updates of installed extensions.

  ## Examples

  ```elixir
  MishkaInstaller.DepUpdateJob.ets()
  ```
  """
  def ets() do
    case ETS.Set.new(
           name: @ets_table,
           protection: :public,
           read_concurrency: true,
           write_concurrency: true
         ) do
      {:ok, set} ->
        Logger.info("Dependency Update ETS storage was started")
        set

      {:error, :table_already_exists} ->
        ETS.Set.wrap_existing!(@ets_table)
    end
  end
end
