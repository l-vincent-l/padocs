defmodule Textexp.SqliteRepo.Migrations.AddDocumentsParent do
  @moduledoc """
  Sub-documents: a document's parent, `NULL` for a document at the root. A
  document goes with its parent (`ON DELETE CASCADE`).
  """
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :parent_id,
          references(:documents,
            column: :id,
            name: "documents_parent_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          )
    end

    # Finding the children of a document
    create index(:documents, [:parent_id])
  end
end
