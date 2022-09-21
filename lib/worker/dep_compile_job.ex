defmodule MishkaInstaller.DepCompileJob do
  @moduledoc """
  With the assistance of this module, you will be able to construct a queue to process and install extensions.

  This module's responsibility includes reactivating the queue using the `MishkaInstaller.Installer.DepChangesProtector` module as one of its tasks.
  """
  use Oban.Worker, queue: :compile_events, max_attempts: 1
  alias MishkaInstaller.Installer.DepHandler
  require Logger

  @doc false
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"app" => app, "type" => type}}) when is_atom(type),
    do: run_compile(app, type)

  def perform(%Oban.Job{args: %{"app" => app, "type" => type}}) when is_binary(type),
    do: run_compile(app, String.to_atom(type))

  def perform(%Oban.Job{args: %{"app" => app, "type" => _type}}), do: run_compile(app, :cmd)

  @doc """
  Register an extension to the compiling queue.
  With the assistance of this function, you will be able to construct a queue,
  download and upload plugins in a sequential fashion from a variety of sources, and register them in your system.


  ## Examples

  ```elixir
  MishkaInstaller.DepCompileJob.add_job("mishka_installer", :cmd)
  # or
  MishkaInstaller.DepCompileJob.add_job("mishka_installer", :port)
  ```
  """
  @spec add_job(String.t(), atom()) :: {:error, any} | {:ok, Oban.Job.t()}
  def add_job(app, type) do
    %{app: app, type: type}
    |> MishkaInstaller.DepCompileJob.new(queue: :compile_events)
    |> Oban.insert()
  end

  defp run_compile(app, type) do
    # TODO: it should be call from lib library_maker
    # TODO: if library_maker has error what we should do?
    Logger.warn("Try to re-compile the request of DepCompileJob")
    DepHandler.create_mix_file_and_start_compile(app, type)
    Oban.pause_queue(queue: :compile_events)
    :ok
  end
end
