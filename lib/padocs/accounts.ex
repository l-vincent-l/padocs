defmodule Padocs.Accounts do
  @moduledoc """
  The accounts, and the ways of signing in to them: a password, a link sent by
  email ("magic link"), or a GitHub or GitLab account. Signing in gives a
  session token (see `Padocs.Accounts.UserToken`).

  An account registered with a password can be used at once; a link is sent to
  confirm its address, used signed in to the account. Using a sign-in link or a
  password reset link also confirms it, as does GitHub or GitLab for the
  addresses they verified.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Padocs.Accounts.{User, UserIdentity, UserNotifier, UserToken}
  alias Padocs.SqliteRepo, as: Repo

  ## Users

  def get_user_by_email(email) when is_binary(email), do: Repo.one(User.by_email_query(email))

  @doc "The user of `email`, if `password` is theirs."
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  @doc "The users of the given ids, e.g. the authors of comments."
  def list_users_by_ids(ids) do
    ids = for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], do: id
    Repo.all(from u in User, where: u.id in ^ids)
  end

  ## Registration with a password

  @doc "An empty registration form's changeset."
  def change_registration(attrs \\ %{}) do
    %User{} |> User.email_changeset(attrs) |> User.password_changeset(attrs)
  end

  @doc """
  Registers a user with an email address and a password, and sends them the
  link confirming the address, built by `confirm_url` from its token.
  """
  def register_user(attrs, confirm_url) do
    with {:ok, user} <- Repo.insert(change_registration(attrs)) do
      deliver_confirmation_instructions(user, confirm_url)
      {:ok, user}
    end
  end

  @doc "Sends the link confirming the address of a user who has not confirmed it."
  def deliver_confirmation_instructions(%User{confirmed_at: nil} = user, confirm_url) do
    UserNotifier.deliver_confirmation_instructions(
      user,
      confirm_url.(insert_link_token(user, "confirm"))
    )
  end

  def deliver_confirmation_instructions(%User{}, _confirm_url), do: {:error, :already_confirmed}

  @doc """
  Confirms the address of `user`, the user of a confirmation link.

  Whoever registered may not own the address: the owner of the address, who
  receives the link, must not confirm an account whose password someone else
  chose, and that they would then share. So the link is only used by the
  user signed in to the account; the owner of the address who did not
  register resets the password instead.
  """
  def confirm_user(%User{id: user_id}, token) do
    with {%User{id: ^user_id} = user, _token} <- get_by_link_token(token, "confirm"),
         {:ok, {user, _expired}} <-
           user |> User.confirm_changeset() |> update_user_and_delete_tokens(["confirm"]) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  ## Links sent by email

  @doc "The user of a link's token for `context`, if valid."
  def get_user_by_link_token(token, context) do
    case get_by_link_token(token, context) do
      {user, _token} -> user
      nil -> nil
    end
  end

  defp get_by_link_token(token, context) do
    case UserToken.link_user_query(token, context) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  defp insert_link_token(user, context) do
    {token, user_token} = UserToken.build_link_token(user, context)
    Repo.insert!(user_token)
    token
  end

  ## Sign-in links

  @doc """
  Sends a sign-in link, built by `login_url` from its token, to `email`. An
  unknown address gets an account, confirmed when the link is used.
  """
  def deliver_login_instructions(email, login_url) do
    with {:ok, user} <- get_or_register_by_email(email) do
      UserNotifier.deliver_login_instructions(user, login_url.(insert_link_token(user, "login")))
    end
  end

  defp get_or_register_by_email(email) do
    case get_user_by_email(email) do
      nil -> %User{} |> User.email_changeset(%{email: email}) |> Repo.insert()
      user -> {:ok, user}
    end
  end

  @doc """
  Signs in the user of a sign-in link: `{:ok, {user, expired_tokens}}`. The
  first use of a link confirms the account.

  An unconfirmed account with a password is refused: whoever chose the
  password may not own the address, and would keep access to the account once
  its owner signs in. Its owner confirms it with the link sent at
  registration, or resets the password.
  """
  def login_user_by_magic_link(token) do
    case get_by_link_token(token, "login") do
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when is_binary(hash) ->
        {:error, :unconfirmed}

      {%User{confirmed_at: nil} = user, _token} ->
        user |> User.confirm_changeset() |> update_user_and_delete_tokens(:all)

      {user, user_token} ->
        Repo.delete!(user_token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  ## Password reset

  @doc """
  Sends a password reset link, built by `reset_url` from its token, to the
  user of `email`, if any. The reply does not tell whether there is one.
  """
  def deliver_reset_password_instructions(email, reset_url) do
    if user = get_user_by_email(email) do
      UserNotifier.deliver_reset_password_instructions(
        user,
        reset_url.(insert_link_token(user, "reset"))
      )
    end

    :ok
  end

  def change_password(attrs \\ %{}), do: User.password_changeset(%User{}, attrs)

  @doc """
  Sets the password of the user of a reset link, confirms their account and
  signs out all their sessions: `{:ok, {user, expired_tokens}}`.
  """
  def reset_password(token, attrs) do
    case get_by_link_token(token, "reset") do
      {user, _token} ->
        user
        |> User.password_changeset(attrs)
        |> Changeset.change(confirmed_at: user.confirmed_at || DateTime.utc_now())
        |> update_user_and_delete_tokens(:all)

      nil ->
        {:error, :not_found}
    end
  end

  ## Sessions

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "The `{user, inserted_at}` of a session token, or nil."
  def get_user_by_session_token(token), do: Repo.one(UserToken.session_user_query(token))

  def delete_user_session_token(token) do
    Repo.delete_all(from t in UserToken, where: t.token == ^token and t.context == "session")
    :ok
  end

  # Updates the user and deletes their tokens of `contexts`; the deleted
  # tokens are returned, to disconnect their sessions.
  defp update_user_and_delete_tokens(changeset, contexts) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        expired = Repo.all(UserToken.user_tokens_query(user, contexts))
        Repo.delete_all(UserToken.user_tokens_query(user, contexts))
        {:ok, {user, expired}}
      end
    end)
  end

  ## GitHub and GitLab

  @doc """
  Signs in, or registers, the owner of a GitHub or GitLab account (`strategy`),
  from what the provider says of it (`user_info`, as given by Assent).

  A returning user is recognised by the account's identifier. Otherwise its
  email address is used, which the provider must have verified: anyone could
  declare someone else's address there, and get here a confirmed account in
  their name. An existing account with that address is only signed in if its
  owner confirmed it: whoever controls the address at the provider would
  otherwise take over an account its owner never validated.
  """
  def sign_in_with_provider(strategy, user_info, oauth_tokens) do
    uid = to_string(user_info["sub"])

    Repo.transact(fn ->
      identity = Repo.get_by(UserIdentity, strategy: strategy, uid: uid)

      with {:ok, user} <- identity_user(identity, user_info),
           {:ok, _identity} <- put_identity(identity, user, strategy, uid, oauth_tokens) do
        {:ok, user}
      end
    end)
  end

  defp identity_user(%UserIdentity{user_id: user_id}, _user_info),
    do: {:ok, Repo.get!(User, user_id)}

  defp identity_user(nil, %{"email_verified" => true, "email" => email}) when is_binary(email) do
    case get_user_by_email(email) do
      nil ->
        %User{}
        |> User.email_changeset(%{email: email})
        |> Changeset.change(confirmed_at: DateTime.utc_now())
        |> Repo.insert()

      %User{confirmed_at: nil} ->
        {:error, :unconfirmed_account}

      user ->
        {:ok, user}
    end
  end

  defp identity_user(nil, _user_info), do: {:error, :unverified_email}

  defp put_identity(identity, user, strategy, uid, oauth_tokens) do
    expires_at =
      case oauth_tokens["expires_in"] do
        seconds when is_integer(seconds) -> DateTime.add(DateTime.utc_now(), seconds)
        _ -> nil
      end

    (identity || %UserIdentity{strategy: strategy, uid: uid, user_id: user.id})
    |> Changeset.change(
      access_token: oauth_tokens["access_token"],
      access_token_expires_at: expires_at,
      refresh_token: oauth_tokens["refresh_token"]
    )
    |> Repo.insert_or_update()
  end
end
