defmodule Padocs.SqliteRepo do
  # A local SQLite file, or a libSQL server: see :repo_adapter in
  # config/config.exs.
  use Ecto.Repo,
    otp_app: :padocs,
    adapter: Application.compile_env(:padocs, :repo_adapter, Ecto.Adapters.SQLite3)
end
