defmodule Padocs.Accounts.UserToken do
  @moduledoc """
  The tokens of a user: their sessions, and the links sent by email.

  A session token is kept in the signed session cookie, so it is stored as is:
  deleting it signs the session out. A link's token is sent by email and only
  its hash is stored, so that reading the database does not give access to the
  accounts. A link is only valid for the address it was sent to.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Padocs.Accounts.User

  @rand_size 32
  @session_validity_in_days 14

  # How long a link sent by email stays valid, by context: short for the
  # links that sign in.
  @link_validity_in_minutes %{
    "login" => 15,
    "reset" => 24 * 60,
    "confirm" => 7 * 24 * 60
  }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A new session token of `user`, and its record."
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", user_id: user.id}}
  end

  @doc """
  The query of the `{user, inserted_at}` of a session token, if it has not
  expired.
  """
  def session_user_query(token) do
    from t in __MODULE__,
      where: t.token == ^token and t.context == "session",
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      join: u in assoc(t, :user),
      select: {u, t.inserted_at}
  end

  @doc """
  A new token of a link sent to `user` for `context` (`"login"`, `"reset"` or
  `"confirm"`): the token for the link, and the record of its hash.
  """
  def build_link_token(user, context) when is_map_key(@link_validity_in_minutes, context) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: :crypto.hash(:sha256, token),
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  The query of the `{user, token}` of a link's token for `context`, if it has
  not expired and the user's address is still the one it was sent to.
  """
  def link_user_query(token, context) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false) do
      {:ok,
       from(t in __MODULE__,
         where: t.token == ^:crypto.hash(:sha256, decoded) and t.context == ^context,
         where: t.inserted_at > ago(^@link_validity_in_minutes[context], "minute"),
         join: u in assoc(t, :user),
         where: t.sent_to == u.email,
         select: {u, t}
       )}
    end
  end

  @doc "The query of the tokens of `user`, of the given contexts or all."
  def user_tokens_query(user, contexts \\ :all)

  def user_tokens_query(user, :all), do: from(t in __MODULE__, where: t.user_id == ^user.id)

  def user_tokens_query(user, contexts),
    do: from(t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts)
end
