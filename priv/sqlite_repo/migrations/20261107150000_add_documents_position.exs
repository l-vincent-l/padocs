defmodule Padocs.SqliteRepo.Migrations.AddDocumentsPosition do
  @moduledoc """
  The order of the sub-documents of a document: `position`, from 0. The
  existing ones keep the order they had, that of their creation.
  """
  use Ecto.Migration

  def up do
    alter table(:documents) do
      add :position, :integer
    end

    execute """
    UPDATE documents
    SET position = (
      SELECT count(*) FROM documents AS sibling
      WHERE sibling.parent_id = documents.parent_id
        AND (sibling.inserted_at < documents.inserted_at
          OR (sibling.inserted_at = documents.inserted_at AND sibling.id < documents.id))
    )
    WHERE parent_id IS NOT NULL
    """
  end

  def down do
    alter table(:documents) do
      remove :position
    end
  end
end
