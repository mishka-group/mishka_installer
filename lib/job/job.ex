defmodule MishkaInstaller.Job do
  @spec start_oban_in_runtime :: {:error, any} | {:ok, pid}
  def start_oban_in_runtime() do
    Application.put_env(:mishka_installer, Oban,
      repo: MishkaInstaller.repo,
      plugins: [Oban.Plugins.Pruner],
      queues: [default: 10]
    )
    # Ref: https://elixirforum.com/t/how-to-start-oban-out-of-application-ex/48417/6
    DynamicSupervisor.start_child(
      MishkaInstaller.RunTimeObanSupervisor,
      {Oban, Application.fetch_env!(:mishka_installer, Oban)}
    )
  end
end
