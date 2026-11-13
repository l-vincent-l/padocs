defmodule Padocs.Document.Membership do
  @moduledoc """
  A user's access to a document they do not own: `:editor` (read and write) or
  `:viewer` (read only). A document or a user deleted takes its memberships
  along (`ON DELETE CASCADE`).

  The owner shares the document by email address (`share_changeset/2`, whose
  `email` is only used to find the user).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "memberships" do
    field :role, Ecto.Enum, values: [:editor, :viewer]
    field :email, :string, virtual: true
    belongs_to :document, Padocs.Document.Document
    belongs_to :user, Padocs.Accounts.User
  end

  def share_changeset(membership, attrs) do
    membership
    |> cast(attrs, [:email, :role])
    |> validate_required([:email, :role])
  end
end
