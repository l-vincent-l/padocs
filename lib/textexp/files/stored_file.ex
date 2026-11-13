defmodule Textexp.Files.StoredFile do
  @moduledoc """
  A file of a document, an image: its bytes are in the storage under
  `Textexp.Files.key/1`. `document` is `nil` for a file uploaded for an import
  not done yet, which only its `owner` reads. Deleted with its document
  (`ON DELETE CASCADE`), its bytes by `Textexp.Files.delete_for_documents/1`.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "files" do
    belongs_to :document, Textexp.Document.Document
    belongs_to :owner, Textexp.Accounts.User
    field :content_type, :string
    field :size, :integer
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
