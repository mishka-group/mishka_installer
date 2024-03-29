defmodule MishkaInstaller.Dependency do
  @moduledoc """
  This module is for communication with `Dependencies` table and has essential functions such as
  adding, editing, deleting, and displaying.
  This module is related to module `MishkaInstaller.Database.DependencySchema`.
  """

  alias MishkaInstaller.Database.DependencySchema
  alias MishkaInstaller.Installer.DepHandler
  import Ecto.Query

  use MishkaDeveloperTools.DB.CRUD,
    module: DependencySchema,
    error_atom: :dependency,
    repo: MishkaInstaller.repo()

  @behaviour MishkaDeveloperTools.DB.CRUD

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_add, 1}
  def create(attrs) do
    crud_add(attrs)
    |> notify_subscribers(:dependency)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_add, 1}
  def create(attrs, allowed_fields) do
    crud_add(attrs, allowed_fields)
    |> notify_subscribers(:dependency)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_edit, 1}
  def edit(attrs) do
    crud_edit(attrs)
    |> notify_subscribers(:dependency)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_edit, 1}
  def edit(attrs, allowed_fields) do
    crud_edit(attrs, allowed_fields)
    |> notify_subscribers(:dependency)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_delete, 1}
  def delete(id) do
    crud_delete(id)
    |> notify_subscribers(:dependency)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_get_record, 1}
  def show_by_id(id) do
    crud_get_record(id)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_get_by_field, 2}
  def show_by_name(app) do
    crud_get_by_field("app", app)
  end

  @doc """
  This is an aggregation function that includes editing or adding.
  """
  @spec create_or_update(map()) :: tuple()
  def create_or_update(data) do
    case show_by_name(data.app) do
      {:error, :get_record_by_field, :dependency} ->
        create(data)

      {:ok, :get_record_by_field, :dependency, record_info} ->
        if Version.compare(data.version, record_info.version) == :gt do
          update_app_version(record_info.id, data)
        else
          {:error, :update_app_version, :older_version}
        end
    end
  end

  @doc """
  Show all dependencies.
  """
  def dependencies() do
    from(dep in DependencySchema)
    |> fields()
    |> MishkaInstaller.repo().all()
  end

  def dependencies(:struct) do
    dependencies()
    |> Enum.map(&struct(DepHandler, &1))
  end

  @doc """
  This is an aggregation function that includes editing a type of app.
  """
  @spec change_dependency_type_with_app(String.t(), String.t()) ::
          {:ok, :change_dependency_type_with_app, map()}
          | {:error, :change_dependency_type_with_app, :dependency, atom() | map()}
  def change_dependency_type_with_app(app, dependency_type) do
    with {:ok, :get_record_by_field, :dependency, record_info} <-
           MishkaInstaller.Dependency.show_by_name(app),
         {:ok, :edit, :dependency, repo_data} <-
           MishkaInstaller.Dependency.edit(%{
             "id" => record_info.id,
             "dependency_type" => dependency_type
           }) do
      {:ok, :change_dependency_type_with_app, repo_data}
    else
      {:error, :get_record_by_field, :dependency} ->
        {:error, :change_dependency_type_with_app, :dependency, :not_found}

      {:error, :edit, action, :dependency} when action in [:uuid, :get_record_by_id] ->
        {:error, :change_dependency_type_with_app, :dependency, :not_found}

      {:error, :edit, :dependency, repo_error} ->
        {:error, :change_dependency_type_with_app, :dependency, repo_error}
    end
  end

  defp fields(query) do
    from([dep] in query,
      order_by: [desc: dep.inserted_at, desc: dep.id],
      select: %{
        id: dep.id,
        app: dep.app,
        version: dep.version,
        type: dep.type,
        url: dep.url,
        git_tag: dep.git_tag,
        custom_command: dep.custom_command,
        dependency_type: dep.dependency_type,
        dependencies: dep.dependencies
      }
    )
  end

  @doc """
  If you want to get the latest changes from the `Dependencies` table of your database,
  this function can help you to be subscribed.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(
      MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
      "dependency"
    )
  end

  if Mix.env() == :test do
    defp notify_subscribers(params, _type_send), do: params
  else
    defp notify_subscribers({:ok, action, :dependency, repo_data} = params, type_send) do
      Phoenix.PubSub.broadcast(
        MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
        "dependency",
        {:ok, type_send, action, repo_data}
      )

      params
    end

    defp notify_subscribers(params, _), do: params
  end

  defp convert_map_from_atom_to_string(map) do
    for {key, val} <- map, into: %{} do
      {to_string(key), to_string(val)}
    end
  end

  defp update_app_version(id, data) do
    crud_edit(
      Map.merge(convert_map_from_atom_to_string(data), %{
        "id" => id,
        "dependency_type" => "force_update"
      })
    )
  end
end
