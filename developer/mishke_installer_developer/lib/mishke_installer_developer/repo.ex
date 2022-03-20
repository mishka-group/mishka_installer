defmodule MishkeInstallerDeveloper.Repo do
  use Ecto.Repo,
    otp_app: :mishke_installer_developer,
    adapter: Ecto.Adapters.Postgres
end
