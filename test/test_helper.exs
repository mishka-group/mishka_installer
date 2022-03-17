ExUnit.start()
alias Ecto.Integration.TestRepo
Logger.configure(level: :error)
Application.put_env(
  :ecto,
  TestRepo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_DEVELOPERT_URL", "postgresql://postgres:postgres@localhost:5432/mishka_installer_test"),
  pool: Ecto.Adapters.SQL.Sandbox,
  queue_target: 5000,
  pool_size: 20
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.Postgres
end

Application.put_env(:mishka_installer, :basic, repo: TestRepo, pubsub: nil)

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(TestRepo, :temporary)

_ = Ecto.Adapters.Postgres.storage_down(TestRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(TestRepo.config())

{:ok, _pid} = TestRepo.start_link()

Code.require_file("test_activity_table.exs", __DIR__)
:ok = Ecto.Migrator.up(TestRepo, 0, MishkaInstaller.Repo.Migrations.TestActivityTable, log: false)

Code.require_file("test_plugin_table.exs", __DIR__)
:ok = Ecto.Migrator.up(TestRepo, 1, MishkaInstaller.Repo.Migrations.TestPluginTable, log: false)

Process.flag(:trap_exit, true)
