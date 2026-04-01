defmodule TokenGuard.Repo do
  use Ecto.Repo,
    otp_app: :token_guard,
    adapter: Ecto.Adapters.Postgres
end
