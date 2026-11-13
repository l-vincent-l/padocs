defmodule Padocs.SqliteRepo.Migrations.AddUsersLastDocument do
  @moduledoc """
  The document each user opened last, opened again at `/documents`. Emptied
  when the document is deleted.
  """
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :last_document_id,
          references(:documents,
            column: :id,
            name: "users_last_document_id_fkey",
            type: :uuid,
            on_delete: :nilify_all
          )
    end
  end
end
