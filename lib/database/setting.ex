defmodule MishkaInstaller.Setting do

  alias MishkaInstaller.Database.SettingSchema
  import Ecto.Query
  use MishkaDeveloperTools.DB.CRUD,
          module: SettingSchema,
          error_atom: :setting,
          repo: MishkaInstaller.repo

  @behaviour MishkaDeveloperTools.DB.CRUD

  def subscribe do
    Phoenix.PubSub.subscribe(MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub, "setting")
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_add, 1}
  def create(attrs) do
    crud_add(attrs)
    |> notify_subscribers(:setting)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_add, 1}
  def create(attrs, allowed_fields) do
    crud_add(attrs, allowed_fields)
    |> notify_subscribers(:setting)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_edit, 1}
  def edit(attrs) do
    crud_edit(attrs)
    |> notify_subscribers(:setting)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_edit, 1}
  def edit(attrs, allowed_fields) do
    crud_edit(attrs, allowed_fields)
    |> notify_subscribers(:setting)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_delete, 1}
  def delete(id) do
    crud_delete(id)
    |> notify_subscribers(:setting)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_get_record, 1}
  def show_by_id(id) do
    crud_get_record(id)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_get_by_field, 2}
  def show_by_name(name) do
    crud_get_by_field("name", name)
  end

  def add_or_edit_by_name(data) do
    case show_by_name("#{data.name}") do
      {:ok, :get_record_by_field, :setting, repo_data} -> edit(data |> Map.merge(%{id: repo_data.id}))
      _ -> create(data)
    end
  end

  def settings() do
    from(plg in SettingSchema)
    |> fields()
    |> MishkaInstaller.repo.all()
  end

  defp fields(query) do
    from [set] in query,
    order_by: [desc: set.inserted_at, desc: set.id],
    select: %{
      name: set.name,
      configs: set.configs,
    }
  end

  if Mix.env() == :test do
    def notify_subscribers(params, _type_send), do: params
  else
    def notify_subscribers({:ok, action, :activity, repo_data} = params, type_send) do
      Phoenix.PubSub.broadcast(MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub, "setting", {type_send, :ok, action, repo_data})
      params
    end

    def notify_subscribers(params, _), do: params
  end
end
