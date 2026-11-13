defmodule Padocs.Document.TagDocument do
  @moduledoc """
  A tag put on a document. Deleted with its document or its tag
  (`ON DELETE CASCADE`).
  """
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id
  schema "documents_tags" do
    belongs_to :document, Padocs.Document.Document, primary_key: true
    belongs_to :tag, Padocs.Document.Tag, primary_key: true
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
