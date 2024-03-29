defmodule MishkaInstaller.Activity do
  @moduledoc """
  This module is for communication with `Activities` table and has essential functions such as
  adding, editing, deleting, and displaying.
  This module is related to module `MishkaInstaller.Database.ActivitySchema`.
  """
  alias MishkaInstaller.Database.ActivitySchema

  use MishkaDeveloperTools.DB.CRUD,
    module: ActivitySchema,
    error_atom: :activity,
    repo: MishkaInstaller.repo()

  @behaviour MishkaDeveloperTools.DB.CRUD

  @doc """
  If you want to get the latest changes from the `Activities` table of your database,
  this function can help you to be subscribed.
  """
  @spec subscribe :: :ok | {:error, {:already_registered, pid}}
  def subscribe do
    Phoenix.PubSub.subscribe(
      MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
      "activity"
    )
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_add, 1}
  def create(attrs) do
    crud_add(attrs)
    |> notify_subscribers(:activity)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_edit, 1}
  def edit(attrs) do
    crud_edit(attrs)
    |> notify_subscribers(:activity)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_edit, 1}
  def edit(attrs, allowed_fields) do
    crud_edit(attrs, allowed_fields)
    |> notify_subscribers(:activity)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_delete, 1}
  def delete(id) do
    crud_delete(id)
    |> notify_subscribers(:activity)
  end

  @doc delegate_to: {MishkaDeveloperTools.DB.CRUD, :crud_get_record, 1}
  def show_by_id(id) do
    crud_get_record(id)
  end

  @doc """
  This function helps to save the latest activities in different nodes without waiting for a response.
  """
  @spec create_activity_by_start_child(map(), map()) ::
          :ignore | {:error, any} | {:ok, pid} | {:ok, pid, any}
  def create_activity_by_start_child(params, extra \\ %{}) do
    Task.Supervisor.start_child(__MODULE__, fn ->
      convert_task_to_db(params, extra)
    end)
  end

  @doc """
  This function helps to save the latest activities in different nodes within waiting for a response.
  """
  @spec create_activity_by_task(map(), map()) :: Task.t()
  def create_activity_by_task(params, extra \\ %{}) do
    Task.Supervisor.async_nolink(__MODULE__, fn ->
      convert_task_to_db(params, extra)
    end)
  end

  defp convert_task_to_db(params, extra) do
    create(%{
      type: params.type,
      section: params.section,
      section_id: params.section_id,
      priority: params.priority,
      status: params.status,
      action: params.action,
      user_id: params.user_id,
      extra: %{extra: extra}
    })
  end

  if Mix.env() == :test do
    defp notify_subscribers(params, _type_send), do: params
  else
    defp notify_subscribers({:ok, _, :activity, repo_data} = params, type_send) do
      Phoenix.PubSub.broadcast(
        MishkaInstaller.get_config(:pubsub) || MishkaInstaller.PubSub,
        "activity",
        {type_send, :ok, repo_data}
      )

      params
    end

    defp notify_subscribers(params, _), do: params
  end
end
