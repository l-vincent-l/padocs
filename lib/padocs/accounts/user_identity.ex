defmodule Padocs.Accounts.UserIdentity do
  @moduledoc """
  A GitHub or GitLab account linked to a user: the provider's stable
  identifier of the account (`uid`, for the `strategy`) and its OAuth tokens.
  A returning user is recognised by it, not by their email address.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "user_identities" do
    field :strategy, :string
    field :uid, :string
    field :access_token, :string, redact: true
    field :access_token_expires_at, :utc_datetime_usec
    field :refresh_token, :string, redact: true
    belongs_to :user, Padocs.Accounts.User
  end
end
