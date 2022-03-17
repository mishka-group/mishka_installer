ExUnit.start()
alias Ecto.Integration.TestRepo

Application.put_env(
  :ecto,
  TestRepo,
  adapter: Ecto.Adapters.Postgres,
  url: System.get_env("DATABASE_DEVELOPERT_URL", "postgresql://postgres:postgres@localhost:5432/mishka_installer_test"),
  pool: Ecto.Adapters.SQL.Sandbox
)

defmodule Ecto.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.Postgres
end

{:ok, _} = Ecto.Adapters.Postgres.ensure_all_started(TestRepo, :temporary)

_ = Ecto.Adapters.Postgres.storage_down(TestRepo.config())
:ok = Ecto.Adapters.Postgres.storage_up(TestRepo.config())

{:ok, _pid} = TestRepo.start_link()

Code.require_file("test_tables.exs", __DIR__)

:ok = Ecto.Migrator.up(TestRepo, 0, MishkaInstaller.Repo.Migrations.TestActivityTable, log: false)
:ok = Ecto.Migrator.up(TestRepo, 0, MishkaInstaller.Repo.Migrations.TestCategoryTable, log: false)
Ecto.Adapters.SQL.Sandbox.mode(TestRepo, :manual)
Process.flag(:trap_exit, true)
end
