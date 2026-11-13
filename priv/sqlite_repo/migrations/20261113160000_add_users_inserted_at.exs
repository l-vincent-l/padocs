defmodule Padocs.SqliteRepo.Migrations.AddUsersInsertedAt do
  @moduledoc """
  When an account was registered: the delay to confirm its address counts
  from then (see `Padocs.Accounts.confirmation_deadline/1`). The existing
  accounts count from this migration, so they get the whole delay.
  """
  use Ecto.Migration

  def up do
    # SQLite does not add a column with a default that is not a constant:
    # nullable, then filled.
    alter table(:users) do
      add :inserted_at, :utc_datetime
    end

    execute "UPDATE users SET inserted_at = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"
  end

  def down do
    alter table(:users) do
      remove :inserted_at
    end
  end
end
