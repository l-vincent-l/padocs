defmodule Padocs.SqliteRepo.Migrations.ReplaceTokensWithUsersTokens do
  @moduledoc """
  The JWTs of AshAuthentication (`tokens`) give way to random tokens, of which
  only the hash is stored for the links sent by email (see
  `Padocs.Accounts.UserToken`). Open sessions are signed out.
  """

  use Ecto.Migration

  def up do
    drop table(:tokens)

    create table(:users_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :text, null: false
      add :sent_to, :text
      add :inserted_at, :utc_datetime, null: false
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end

  def down do
    drop table(:users_tokens)

    create table(:tokens, primary_key: false) do
      add :updated_at, :utc_datetime_usec, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :extra_data, :map
      add :purpose, :text, null: false
      add :expires_at, :utc_datetime, null: false
      add :subject, :text, null: false
      add :jti, :text, null: false, primary_key: true
    end
  end
end
