defmodule Textexp.Document.Document do
  @moduledoc """
  A collaborative document.

  Its Yjs content is the log of its updates (see `Textexp.Document.Update`),
  appended about every second while it is being edited (see
  `Textexp.Document.YPersistence`). `snapshot` caches their merge up to
  `snapshot_update_id`, rewritten by the compaction (see
  `Textexp.Document.History`): the content is the snapshot plus the updates
  after it. `excerpt` holds the first lines of its body, saved with each
  update to preview the document without decoding it, and `updated_at` is
  the last one (renaming also changes it).

  A document can be the sub-document of another, its `parent`, from which it
  inherits the accesses (see `Textexp.Document`).

  The sub-documents of a document are in the order of their `position`, from
  0 (see `Textexp.Document.place_document/4`).

  A deleted document goes to the trash with its sub-documents: `deleted_at`
  is set on each, `deleted_by` is the user who deleted it. Nobody reads it
  there; its owner, maybe by inheritance, restores it, or deletes it for good
  (see `Textexp.Document.trash_document/2`).

  `public_token` is the secret of its public link, which anyone can read it
  with, read-only; `nil` without one (see
  `Textexp.Document.enable_public_link/2`). It is never read along with the
  document: only its owner sees it.

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
    field :snapshot_update_id, :integer, default: 0
    field :excerpt, :string
    field :role, Ecto.Enum, values: [:owner, :editor, :viewer], virtual: true
    field :snippet, :any, virtual: true
    field :deleted_at, :utc_datetime_usec
    field :position, :integer
    field :public_token, :string
    belongs_to :owner, Textexp.Accounts.User
    belongs_to :deleted_by, Textexp.Accounts.User
    belongs_to :parent, __MODULE__
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :memberships, Textexp.Document.Membership
    many_to_many :tags, Textexp.Document.Tag, join_through: Textexp.Document.TagDocument
    timestamps(type: :utc_datetime_usec)
  end
end
