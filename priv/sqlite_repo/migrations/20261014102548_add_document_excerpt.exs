defmodule Padocs.SqliteRepo.Migrations.AddDocumentExcerpt do
  @moduledoc """
  Adds `documents.excerpt`, the first lines of the body saved along with the
  snapshot, and fills it for existing documents from their snapshot (without
  touching `updated_at`, which orders the document list).
  """

  use Ecto.Migration

  def up do
    alter table(:documents) do
      add :excerpt, :text
    end

    flush()

    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        repo(),
        "SELECT id, snapshot FROM documents WHERE snapshot IS NOT NULL"
      )

    for [id, snapshot] <- rows do
      doc = Yex.Doc.new()
      Yex.apply_update(doc, snapshot)
      excerpt = Padocs.Document.Body.excerpt(doc)

      Ecto.Adapters.SQL.query!(repo(), "UPDATE documents SET excerpt = ? WHERE id = ?", [
        excerpt,
        id
      ])
    end
  end

  def down do
    alter table(:documents) do
      remove :excerpt
    end
  end
end
