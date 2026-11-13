defmodule Textexp.SqliteRepo.Migrations.AddDocumentsPublicToken do
  @moduledoc """
  The public link of a document: `public_token`, the secret of its URL, which
  lets anyone read it; `nil` without a link (see
  `Textexp.Document.enable_public_link/2`).
  """
  use Ecto.Migration

  def change do
    alter table(:documents) do
      add :public_token, :string
    end

    create unique_index(:documents, [:public_token])
  end
end
