defmodule Padocs.SqliteRepo.Migrations.AddDocumentTag do
  @moduledoc """
  Tags, shared by everyone (one per lowercased label, `key`), and the
  documents carrying them. A link goes with its document or its tag.
  """
  use Ecto.Migration

  def change do
    create table(:tags, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :label, :text, null: false
      add :key, :text, null: false
      add :color, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:tags, [:key], name: "tags_unique_key_index")

    create table(:documents_tags, primary_key: false) do
      add :document_id,
          references(:documents,
            column: :id,
            name: "documents_tags_document_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false,
          primary_key: true

      add :tag_id,
          references(:tags,
            column: :id,
            name: "documents_tags_tag_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false,
          primary_key: true

      add :inserted_at, :utc_datetime_usec, null: false
    end

    # Finding the documents of a tag (search by tag)
    create index(:documents_tags, [:tag_id])
  end
end
