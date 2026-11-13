defmodule Padocs.Accounts.User do
  @moduledoc """
  An account. Its owner signs in with a password, a link sent by email, or a
  GitHub or GitLab account (see `Padocs.Accounts.UserIdentity`). Email
  addresses are compared without case.
  """
  use Ecto.Schema
  # The messages of the changesets, translated where shown (see
  # PadocsWeb.CoreComponents.translate_error/1)
  use Gettext, backend: PadocsWeb.Gettext
  import Ecto.Changeset
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime_usec
    # Opened again at /documents (see Padocs.Document.last_opened/1)
    field :last_document_id, :binary_id
    # The language chosen, `nil` for the browser's (see PadocsWeb.Locale)
    field :locale, :string
    # When the account was registered (see Padocs.Accounts.confirmation_deadline/1)
    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The users whose email address is `email`, whatever its case."
  def by_email_query(email) do
    from u in __MODULE__, where: fragment("lower(?)", u.email) == ^String.downcase(email)
  end

  @doc "A new account, or a change of its email address."
  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> update_change(:email, &String.trim/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: dgettext_noop("errors", "is not a valid address")
    )
    |> validate_length(:email, max: 160)
    |> validate_unique_email()
    |> unique_constraint(:email, name: "users_unique_email_index")
  end

  defp validate_unique_email(changeset) do
    with email when is_binary(email) <- get_change(changeset, :email),
         true <- Padocs.SqliteRepo.exists?(by_email_query(email)) do
      add_error(changeset, :email, dgettext_noop("errors", "an account already has this address"))
    else
      _ -> changeset
    end
  end

  @doc """
  Sets the password, hashed. Its confirmation, `password_confirmation`, must
  match it.
  """
  def password_changeset(user, attrs) do
    changeset =
      user
      |> cast(attrs, [:password])
      |> validate_required([:password])
      |> validate_length(:password, min: 8, max: 72, count: :bytes)
      |> validate_confirmation(:password,
        required: true,
        message: dgettext_noop("errors", "does not match")
      )

    if changeset.valid? do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(get_change(changeset, :password)))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc "Confirms the email address."
  def confirm_changeset(user), do: change(user, confirmed_at: DateTime.utc_now())

  @doc """
  Whether `password` is the user's. Without user or password, a hash is still
  computed, so that the time taken does not tell whether the account exists.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
