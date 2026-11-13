defmodule Padocs.Document.Visit do
  @moduledoc """
  When a user last opened a document: their recent documents come first in
  the search modal (see `Padocs.Document.list_recent_documents/2`). Deleted
  with its user or its document (`ON DELETE CASCADE`).
  """
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "document_visits" do
    belongs_to :user, Padocs.Accounts.User, primary_key: true
    belongs_to :document, Padocs.Document.Document, primary_key: true
    field :opened_at, :utc_datetime_usec
  end
end
