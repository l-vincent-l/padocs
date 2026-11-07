defmodule Textexp.Document.Document do
  @moduledoc """
  A collaborative document.

  Its Yjs content is stored in `snapshot`: the full state, rewritten at most
  every 10 s while it is being edited (see `Textexp.Document.YPersistence`).
  `excerpt` holds the first lines of its body, saved along with the snapshot to
  preview the document without decoding it. The snapshot is rewritten on each
  save, so `updated_at` is its last update (renaming also changes it).

  A document can be the sub-document of another, its `parent`, from which it
  inherits the accesses (see `Textexp.Document`).

  The sub-documents of a document are in the order of their `position`, from
  0 (see `Textexp.Document.place_document/4`).

  A deleted document goes to the trash with its sub-documents: `deleted_at`
  is set on each, `deleted_by` is the user who deleted it. Nobody reads it
  there; its owner, maybe by inheritance, restores it, or deletes it for good
  (see `Textexp.Document.trash_document/2`).

  `role` is the reader's right on it, read along with it (see
  `Textexp.Document.get_document/2`); `snippet`, the fragment of its body
  matching a search (see `Textexp.Document.Search`).
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "documents" do
    field :title, :string
    field :snapshot, :binary
    field :excerpt, :string
    field :role, Ecto.Enum, values: [:owner, :editor, :viewer], virtual: true
    field :snippet, :any, virtual: true
    field :deleted_at, :utc_datetime_usec
    field :position, :integer
    belongs_to :owner, Textexp.Accounts.User
    belongs_to :deleted_by, Textexp.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :memberships, Textexp.Document.Membership
    many_to_many :tags, Textexp.Document.Tag, join_through: Textexp.Document.TagDocument
    timestamps(type: :utc_datetime_usec)
  end
end
