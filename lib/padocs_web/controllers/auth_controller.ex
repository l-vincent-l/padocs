defmodule PadocsWeb.AuthController do
  @moduledoc """
  Signing in with a password or a link sent by email, registering, resetting a
  password, confirming an address, signing out. The links sent by email lead
  to a page with a button: following them is not enough, as mail scanners
  open links.
  """
  use PadocsWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Padocs.Accounts
  alias PadocsWeb.UserAuth

  plug :redirect_if_signed_in when action in [:sign_in, :register]

  def sign_in(conn, _params) do
    render(conn, :sign_in, form: to_form(%{}, as: "user"))
  end

  def create_session(conn, %{"user" => %{"email" => email, "password" => password} = params}) do
    user = Accounts.get_user_by_email_and_password(email, password)

    cond do
      # Whether the address has an account is not told.
      is_nil(user) ->
        conn
        |> put_flash(:error, gettext("Incorrect email or password"))
        |> redirect(to: ~p"/sign-in")

      # Told to whoever knows the password only.
      Accounts.confirmation_expired?(user) ->
        conn
        |> put_flash(
          :error,
          gettext(
            "Your email address was not confirmed in time. Reset your password: this confirms your address and lets you sign in again."
          )
        )
        |> redirect(to: ~p"/reset")

      true ->
        conn
        |> put_flash(:info, gettext("You are now signed in"))
        |> UserAuth.log_in_user(user, params)
    end
  end

  def register(conn, _params) do
    render(conn, :register, form: to_form(Accounts.change_registration(), as: "user"))
  end

  def create_user(conn, %{"user" => params}) do
    case Accounts.register_user(params, &url(~p"/confirm_new_user/#{&1}")) do
      {:ok, user} ->
        conn
        |> put_flash(:info, gettext("You are now signed in"))
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:register, form: to_form(changeset, as: "user"))
    end
  end

  def request_magic_link(conn, %{"user" => %{"email" => email}}) do
    Accounts.deliver_login_instructions(email, &url(~p"/magic_link/#{&1}"))

    conn
    |> put_flash(
      :info,
      gettext("If this address is valid, you will receive a sign-in link shortly.")
    )
    |> redirect(to: ~p"/sign-in")
  end

  def magic_link(conn, %{"token" => token}) do
    link_page(conn, token, "login", gettext("Sign in"), ~p"/magic_link/#{token}")
  end

  def sign_in_with_magic_link(conn, %{"token" => token} = params) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, gettext("You are now signed in"))
        |> UserAuth.log_in_user(user, params)

      {:error, :unconfirmed} ->
        conn
        |> put_flash(
          :error,
          gettext(
            "You have already signed in another way, but have not confirmed your account. You can confirm it with the link we sent you, or by resetting your password."
          )
        )
        |> redirect(to: ~p"/sign-in")

      {:error, _} ->
        invalid_link(conn)
    end
  end

  def reset(conn, _params), do: render(conn, :reset, form: to_form(%{}, as: "user"))

  def request_reset(conn, %{"user" => %{"email" => email}}) do
    :ok = Accounts.deliver_reset_password_instructions(email, &url(~p"/password-reset/#{&1}"))

    conn
    |> put_flash(
      :info,
      gettext("If this address has an account, you will receive a reset link shortly.")
    )
    |> redirect(to: ~p"/sign-in")
  end

  def edit_password(conn, %{"token" => token}) do
    if Accounts.get_user_by_link_token(token, "reset") do
      render(conn, :edit_password,
        token: token,
        form: to_form(Accounts.change_password(), as: "user")
      )
    else
      invalid_link(conn)
    end
  end

  def reset_password(conn, %{"token" => token, "user" => params}) do
    case Accounts.reset_password(token, params) do
      {:ok, {user, expired_tokens}} ->
        UserAuth.disconnect_sessions(expired_tokens)

        conn
        |> put_flash(:info, gettext("Your password has successfully been reset"))
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:edit_password, token: token, form: to_form(changeset, as: "user"))

      {:error, _} ->
        invalid_link(conn)
    end
  end

  # The link is used signed in to the account (see Accounts.confirm_user/2):
  # signed out, one signs in first and comes back here.
  def confirm(conn, %{"token" => token}) do
    user = Accounts.get_user_by_link_token(token, "confirm")

    cond do
      is_nil(user) ->
        invalid_link(conn)

      is_nil(conn.assigns.current_user) ->
        conn
        |> put_session(:return_to, ~p"/confirm_new_user/#{token}")
        |> put_flash(
          :info,
          gettext(
            "Sign in to confirm your email address. If you did not create this account, reset its password instead."
          )
        )
        |> redirect(to: ~p"/sign-in")

      conn.assigns.current_user.id != user.id ->
        conn
        |> put_flash(:error, gettext("This link confirms another account: sign out first."))
        |> redirect(to: ~p"/")

      true ->
        render(conn, :email_link,
          title: gettext("Confirm your email address"),
          email: user.email,
          action: ~p"/confirm_new_user/#{token}"
        )
    end
  end

  def confirm_user(conn, %{"token" => token}) do
    with %{} = current_user <- conn.assigns.current_user,
         {:ok, _user} <- Accounts.confirm_user(current_user, token) do
      conn
      |> put_flash(:info, gettext("Your email address has now been confirmed"))
      |> redirect(to: ~p"/documents")
    else
      _ -> invalid_link(conn)
    end
  end

  def sign_out(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> put_flash(:info, gettext("You are now signed out"))
    |> redirect(to: ~p"/")
  end

  # The page of a link sent by email, whose button posts to `action`.
  defp link_page(conn, token, context, title, action) do
    if user = Accounts.get_user_by_link_token(token, context) do
      render(conn, :email_link, title: title, email: user.email, action: action)
    else
      invalid_link(conn)
    end
  end

  defp invalid_link(conn) do
    conn
    |> put_flash(:error, gettext("The link is invalid or it has expired."))
    |> redirect(to: ~p"/sign-in")
  end

  defp redirect_if_signed_in(conn, _opts) do
    if conn.assigns[:current_user],
      do: conn |> redirect(to: ~p"/") |> halt(),
      else: conn
  end
end
