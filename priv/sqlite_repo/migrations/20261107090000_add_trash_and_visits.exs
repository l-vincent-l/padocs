defmodule Textexp.SqliteRepo.Migrations.AddTrashAndVisits do
  @moduledoc """
  The trash: a document deleted by a user goes there with its sub-documents,
  `deleted_at` set on each, `deleted_by_id` the user. And the documents each
  user opened, and when they last did: the recent documents of the search.
  """
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :deleted_at, :utc_datetime_usec

      add :deleted_by_id,
          references(:users,
            column: :id,
            name: "documents_deleted_by_id_fkey",
            type: :uuid,
            on_delete: :nilify_all
          )
    end

    create table(:document_visits, primary_key: false) do
      add :user_id,
          references(:users,
            column: :id,
            name: "document_visits_user_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false,
          primary_key: true

      add :document_id,
          references(:documents,
            column: :id,
            name: "document_visits_document_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false,
          primary_key: true

      add :opened_at, :utc_datetime_usec, null: false
    end

    # The recent documents of a user
    create index(:document_visits, [:user_id, :opened_at])
  end
end
