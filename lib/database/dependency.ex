defmodule MishkaInstaller.Dependency do
  @moduledoc """

  This module can hold your dependencies' information in database

  > Do not use these functions directly, because we do not update JSON file in this module, some functions were prepared in DepHandler module for you.
  """
  alias MishkaInstaller.Database.DependencySchema
  import Ecto.Query
  use MishkaDeveloperTools.DB.CRUD,
          module: DependencySchema,
          error_atom: :dependency,
          repo: MishkaInstaller.repo

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

  def dependencies() do
    from(dep in DependencySchema)
    |> fields()
    |> MishkaInstaller.repo.all()
  end

  def dependencies(:struct) do
    dependencies()
    |> Enum.map(&struct(MishkaInstaller.Installer.DepHandler, &1))
  end

  defp fields(query) do
    from [dep] in query,
    order_by: [desc: dep.inserted_at, desc: dep.id],
    select: %{
      app: dep.app,
      version: dep.version,
      type: dep.type,
      url: dep.url,
      git_tag: dep.git_tag,
      timeout: dep.timeout,
      dependency_type: dep.dependency_type,
      update_server: dep.update_server,
      dependencies: dep.dependencies
    }
  end

  def subscribe do
    Phoenix.PubSub.subscribe(MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub, "dependency")
  end

  if Mix.env() == :test do
    def notify_subscribers(params, _type_send), do: params
  else
    def notify_subscribers({:ok, _, :dependency, repo_data} = params, type_send) do
      Phoenix.PubSub.broadcast(MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub, "activity", {type_send, :ok, repo_data})
      params
    end

    def notify_subscribers(params, _), do: params
  end
end
