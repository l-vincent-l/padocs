defmodule Padocs.Document.Update do
  @moduledoc """
  A Yjs update of a document's content, made between `started_at` and
  `ended_at`: the edits of about a second, appended by the DocServer, or of a
  longer range once merged with its neighbours (see
  `Padocs.Document.History`). Ordered by `id`. Deleted with its document
  (`ON DELETE CASCADE`).
  """
  use Ecto.Schema

  @foreign_key_type :binary_id
  schema "document_updates" do
    belongs_to :document, Padocs.Document.Document
    field :data, :binary
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
  end
end
