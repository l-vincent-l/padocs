defmodule Padocs.SqliteRepo.Migrations.RemoveWritings do
  @moduledoc """
  Document content is now only stored in `documents.snapshot`, rewritten at most
  every 10 s (see `Padocs.Document.YPersistence`). Writings not yet compacted
  into the snapshot are dropped with the table.
  """

  use Ecto.Migration

  def up do
    drop table(:writings)
  end

  def down do
    create table(:writings, primary_key: false) do
      add :document_id,
          references(:documents, column: :id, name: "writings_document_id_fkey", type: :uuid),
          null: false

      add :updated_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
      add :value, :binary, null: false
      add :id, :uuid, null: false, primary_key: true
    end
  end
end
