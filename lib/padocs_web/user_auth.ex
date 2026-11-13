defmodule PadocsWeb.UserAuth do
  @moduledoc """
  The signed-in user of a request (`:current_user`), from the session token
  kept in the session cookie, or else in the remember me cookie.
  """
  use PadocsWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Padocs.Accounts

  # Valid as long as the session token (see UserToken).
  @max_cookie_age_in_days 14
  @remember_me_cookie "_padocs_web_user_remember_me"
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax"
  ]

  # A session token older than this is replaced by a new one, so that an
  # active user stays signed in.
  @session_reissue_age_in_days 7

  @doc """
  Signs the user in, and redirects to the page they wanted
  (`:return_to`) or to the documents. With `"remember_me"`, the session
  survives the browser closing.
  """
  def log_in_user(conn, user, params \\ %{}) do
    return_to = get_session(conn, :return_to)

    conn
    |> create_or_extend_session(user, params)
    |> delete_session(:return_to)
    |> redirect(to: return_to || ~p"/documents")
  end

  @doc "Signs the user out, and closes their LiveViews and document sockets."
  def log_out_user(conn) do
    if token = get_session(conn, :user_token), do: Accounts.delete_user_session_token(token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      PadocsWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    # Sessions still valid elsewhere reconnect.
    if user = conn.assigns[:current_user] do
      PadocsWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
    end

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
  end

  @doc """
  Closes the LiveViews of the given session tokens, e.g. once revoked, and the
  document sockets of their users (sessions still valid reconnect).
  """
  def disconnect_sessions(tokens) do
    for %{token: token} <- tokens do
      PadocsWeb.Endpoint.broadcast(session_topic(token), "disconnect", %{})
    end

    for user_id <- tokens |> Enum.map(& &1.user_id) |> Enum.uniq() do
      PadocsWeb.Endpoint.broadcast("user_socket:#{user_id}", "disconnect", %{})
    end

    :ok
  end

  @doc "Plug assigning `:current_user`, nil when signed out."
  def fetch_current_user(conn, _opts) do
    with {token, conn} <- ensure_user_token(conn),
         {user, inserted_at} <- Accounts.get_user_by_session_token(token) do
      conn
      |> assign(:current_user, user)
      |> maybe_reissue_session_token(user, inserted_at)
    else
      nil -> assign(conn, :current_user, nil)
    end
  end

  @doc "The user of a LiveView or socket session, or nil."
  def session_user(session) do
    with token when is_binary(token) <- session["user_token"],
         {user, _inserted_at} <- Accounts.get_user_by_session_token(token) do
      user
    else
      _ -> nil
    end
  end

  defp ensure_user_token(conn) do
    if token = get_session(conn, :user_token) do
      {token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if token = conn.cookies[@remember_me_cookie] do
        {token, conn |> put_token_in_session(token) |> put_session(:user_remember_me, true)}
      end
    end
  end

  defp maybe_reissue_session_token(conn, user, inserted_at) do
    if DateTime.diff(DateTime.utc_now(), inserted_at, :day) >= @session_reissue_age_in_days,
      do: create_or_extend_session(conn, user, %{}),
      else: conn
  end

  defp create_or_extend_session(conn, user, params) do
    token = Accounts.generate_user_session_token(user)
    remember_me? = get_session(conn, :user_remember_me) || params["remember_me"] == "true"

    conn = if signed_in_as?(conn, user), do: conn, else: renew_session(conn)
    conn = put_token_in_session(conn, token)

    if remember_me? do
      conn
      |> put_session(:user_remember_me, true)
      |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
    else
      conn
    end
  end

  defp signed_in_as?(conn, user),
    do: match?(%{id: id} when id == user.id, conn.assigns[:current_user])

  # A new session id, and an empty session, to avoid fixation attacks.
  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, session_topic(token))
  end

  defp session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"
end
