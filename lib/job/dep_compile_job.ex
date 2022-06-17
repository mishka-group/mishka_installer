defmodule MishkaInstaller.DepCompileJob do
  use Oban.Worker, queue: :compile_events, max_attempts: 1
  alias MishkaInstaller.Installer.DepHandler

  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"app" => app, "type" => type}}) do
    DepHandler.create_mix_file_and_start_compile(app, type)
    Oban.pause_queue(queue: :compile_events)
    :ok
  end
end
