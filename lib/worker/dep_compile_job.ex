defmodule MishkaInstaller.DepCompileJob do
  use Oban.Worker, queue: :compile_events, max_attempts: 1
  alias MishkaInstaller.Installer.DepHandler
  require Logger

  # TODO: check a ref exists or not and after that do compile, if is there so wait
  # TODO: MishkaInstaller.Installer.DepChangesProtector.is_dependency_compiling?()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"app" => app, "type" => type}}) when is_atom(type),
    do: run_compile(app, type)

  def perform(%Oban.Job{args: %{"app" => app, "type" => type}}) when is_binary(type),
    do: run_compile(app, String.to_atom(type))

  def perform(%Oban.Job{args: %{"app" => app, "type" => _type}}), do: run_compile(app, :cmd)

  @spec add_job(String.t(), atom()) :: {:error, any} | {:ok, Oban.Job.t()}
  def add_job(app, type) do
    %{app: app, type: type}
    |> MishkaInstaller.DepCompileJob.new(queue: :compile_events)
    |> Oban.insert()
  end

  defp run_compile(app, type) do
    Logger.warn("Try to re-compile the request of DepCompileJob")
    DepHandler.create_mix_file_and_start_compile(app, type)
    Oban.pause_queue(queue: :compile_events)
    :ok
  end
end
