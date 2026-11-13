defmodule Textexp.SqliteRepo.Migrations.AddFiles do
  @moduledoc """
  The files of the documents, their images (see `Textexp.Files`): the bytes
  are in the storage, under `files/<id>`, the rows say whose they are. A file
  without document was uploaded for an import not done yet, and is only its
  owner's.
  """
  use Ecto.Migration

  def change do
    create table(:files, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :document_id,
          references(:documents,
            column: :id,
            name: "files_document_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          )

      add :owner_id,
          references(:users,
            column: :id,
            name: "files_owner_id_fkey",
            type: :uuid,
            on_delete: :delete_all
          ),
          null: false

      add :content_type, :string, null: false
      add :size, :integer, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:files, [:document_id])
    create index(:files, [:owner_id])
  end
end
