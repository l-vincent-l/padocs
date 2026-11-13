defmodule Padocs.SqliteRepo.Migrations.AddTagSearches do
  @moduledoc """
  The tags each user searched the documents of, and how many times: their
  most searched tags are offered first.
  """
  use Ecto.Migration

  def change do
    create table(:tag_searches, primary_key: false) do
      add :user_id,
          references(:users,
            column: :id,
            name: "tag_searches_user_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false,
          primary_key: true

      add :tag_id,
          references(:tags,
            column: :id,
            name: "tag_searches_tag_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false,
          primary_key: true

      add :count, :integer, null: false, default: 1
      add :searched_at, :utc_datetime_usec, null: false
    end
  end
end
