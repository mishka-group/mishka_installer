defmodule MishkaInstaller.Setting do
  alias MishkaInstaller.Database.SettingSchema
  import Ecto.Query

  use MishkaDeveloperTools.DB.CRUD,
    module: SettingSchema,
    error_atom: :setting,
    repo: MishkaInstaller.repo()

  @behaviour MishkaDeveloperTools.DB.CRUD

  def subscribe do
    Phoenix.PubSub.subscribe(
      MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
      "setting"
    )
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
      {:ok, :get_record_by_field, :setting, repo_data} ->
        edit(data |> Map.merge(%{id: repo_data.id}))

      _ ->
        create(data)
    end
  end

  @spec settings([
          {:conditions, {String.t() | integer(), String.t() | integer()}} | {:filters, map()},
          ...
        ]) :: any
  def settings(conditions: {page, page_size}, filters: filters) do
    try do
      query = from(set in SettingSchema) |> convert_filters_to_where(filters)

      from([set] in query,
        order_by: [desc: set.inserted_at, desc: set.id],
        select: %{
          id: set.id,
          name: set.name,
          configs: set.configs,
          updated_at: set.updated_at,
          inserted_at: set.inserted_at
        }
      )
      |> MishkaInstaller.repo().paginate(page: page, page_size: page_size)
    rescue
      _db_error ->
        case Code.ensure_compiled(module = Scrivener.Page) do
          {:module, _} ->
            struct(module, %{
              entries: [],
              page_number: 1,
              page_size: page_size,
              total_entries: 0,
              total_pages: 1
            })

          {:error, _} ->
            %{entries: [], page_number: 1, page_size: page_size, total_entries: 0, total_pages: 1}
        end
    end
  end

  def settings(filters: filters) do
    try do
      query = from(set in SettingSchema) |> convert_filters_to_where(filters)

      from([set] in query,
        order_by: [desc: set.inserted_at, desc: set.id],
        select: %{
          id: set.id,
          name: set.name,
          configs: set.configs,
          updated_at: set.updated_at,
          inserted_at: set.inserted_at
        }
      )
      |> MishkaInstaller.repo().all()
    rescue
      _db_error -> []
    end
  end

  def settings() do
    from(plg in SettingSchema)
    |> fields()
    |> MishkaInstaller.repo().all()
  end

  defp convert_filters_to_where(query, filters) do
    Enum.reduce(filters, query, fn {key, value}, query ->
      from(set in query, where: field(set, ^key) == ^value)
    end)
  end

  defp fields(query) do
    from([set] in query,
      order_by: [desc: set.inserted_at, desc: set.id],
      select: %{
        name: set.name,
        configs: set.configs
      }
    )
  end

  if Mix.env() == :test do
    defp notify_subscribers(params, _type_send), do: params
  else
    defp notify_subscribers({:ok, action, :setting, repo_data} = params, type_send) do
      Phoenix.PubSub.broadcast(
        MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
        "setting",
        {type_send, :ok, action, repo_data}
      )

      params
    end

    defp notify_subscribers(params, _), do: params
  end

  @spec allowed_fields(:atom | :string) :: nil | list
  def allowed_fields(:atom), do: SettingSchema.__schema__(:fields)

  def allowed_fields(:string),
    do: SettingSchema.__schema__(:fields) |> Enum.map(&Atom.to_string/1)
end
