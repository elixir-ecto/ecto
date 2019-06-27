defmodule Botany.Repo do
  use Ecto.Repo,
    otp_app: :botany,
    adapter: Ecto.Adapters.Postgres
end
