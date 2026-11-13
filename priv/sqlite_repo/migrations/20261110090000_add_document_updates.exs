defmodule Padocs.SqliteRepo.Migrations.AddDocumentUpdates do
  @moduledoc """
  The Yjs log of each document: the updates of its content, appended by its
  DocServer about every second, then merged into ranges, coarser with age:
  the points of its history (see `Padocs.Document.History`).

  `documents.snapshot` becomes a cache of the updates up to
  `snapshot_update_id`. Each existing snapshot becomes the first update of
  its document, so that its history starts with it.
  """
  use Ecto.Migration

  def up do
    create table(:document_updates) do
      add :document_id,
          references(:documents,
            column: :id,
            name: "document_updates_document_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false

      add :data, :binary, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec, null: false
    end

    create index(:document_updates, [:document_id, :id])

    alter table(:documents) do
      add :snapshot_update_id, :integer, null: false, default: 0
    end

    execute """
    INSERT INTO document_updates (document_id, data, started_at, ended_at)
    SELECT id, snapshot, inserted_at, updated_at FROM documents WHERE snapshot IS NOT NULL
    """

    execute """
    UPDATE documents
    SET snapshot_update_id =
      (SELECT max(u.id) FROM document_updates u WHERE u.document_id = documents.id)
    WHERE snapshot IS NOT NULL
    """
  end

  def down do
    alter table(:documents) do
      remove :snapshot_update_id
    end

    drop table(:document_updates)
  end
end
