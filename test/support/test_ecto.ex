defmodule Ecto.Integration.TestRepo do
  @moduledoc """
  This is a test instance of Ecto.Repo
  """
  use Ecto.Repo,
    otp_app: :ecto,
    adapter: Ecto.Adapters.Postgres
end
