defmodule PadocsWeb.AuthControllerTest do
  use PadocsWeb.ConnCase

  alias Padocs.{Accounts, Fixtures}

  # The token of the link to `path` in an email sent.
  defp link_token(path) do
    receive do
      {:email, email} ->
        case Regex.run(~r{#{path}/([\w-]+)}, email.html_body) do
          [_, token] -> token
          nil -> link_token(path)
        end
    after
      0 -> flunk("no email with a link to #{path}")
    end
  end

  defp signed_in_user(conn) do
    with token when is_binary(token) <- get_session(conn, :user_token),
         {user, _} <- Accounts.get_user_by_session_token(token),
         do: user
  end

  describe "registration" do
    test "signs the new user in and sends the confirmation link", %{conn: conn} do
      conn =
        post(conn, ~p"/register", %{
          "user" => %{
            "email" => "new@example.com",
            "password" => "a-long-password",
            "password_confirmation" => "a-long-password"
          }
        })

      assert redirected_to(conn) == ~p"/documents"
      assert %{email: "new@example.com", confirmed_at: nil} = signed_in_user(conn)

      token = link_token("/confirm_new_user")
      user = signed_in_user(conn)
      conn = build_conn() |> Fixtures.log_in(user) |> post(~p"/confirm_new_user/#{token}")
      assert redirected_to(conn) == ~p"/documents"
      assert Accounts.get_user_by_email(user.email).confirmed_at
    end

    # The owner of the address may not be whoever chose the password.
    test "the confirmation link is only used signed in to the account", %{conn: conn} do
      user = Fixtures.register_user()
      token = link_token("/confirm_new_user")

      conn = get(conn, ~p"/confirm_new_user/#{token}")
      assert redirected_to(conn) == ~p"/sign-in"
      assert get_session(conn, :return_to) == ~p"/confirm_new_user/#{token}"

      conn = post(build_conn(), ~p"/confirm_new_user/#{token}")
      refute get_session(conn, :user_token)

      other = build_conn() |> Fixtures.log_in(Fixtures.register_user())
      post(other, ~p"/confirm_new_user/#{token}")

      refute Accounts.get_user_by_email(user.email).confirmed_at
    end

    test "refuses a short password, or a taken address", %{conn: conn} do
      Fixtures.register_user("taken@example.com")

      for {email, password} <- [
            {"short@example.com", "short"},
            {"TAKEN@example.com", "a-long-password"}
          ] do
        conn =
          post(conn, ~p"/register", %{
            "user" => %{
              "email" => email,
              "password" => password,
              "password_confirmation" => password
            }
          })

        assert html_response(conn, 422)
        refute get_session(conn, :user_token)
      end
    end
  end

  describe "password" do
    test "signs in with the right password only, whatever the case of the address", %{conn: conn} do
      user = Fixtures.register_user("Person@example.com")

      conn =
        post(conn, ~p"/sign-in", %{
          "user" => %{"email" => "person@EXAMPLE.com", "password" => Fixtures.password()}
        })

      assert signed_in_user(conn).id == user.id

      conn =
        post(build_conn(), ~p"/sign-in", %{
          "user" => %{"email" => user.email, "password" => "wrong-password"}
        })

      assert redirected_to(conn) == ~p"/sign-in"
      refute get_session(conn, :user_token)
    end

    test "remember me keeps the session in a cookie", %{conn: conn} do
      user = Fixtures.register_user()

      conn =
        post(conn, ~p"/sign-in", %{
          "user" => %{
            "email" => user.email,
            "password" => Fixtures.password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_padocs_web_user_remember_me"]
    end

    test "an address left unconfirmed past the delay no longer signs in", %{conn: conn} do
      user = Fixtures.register_user()

      user
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(:second), -8, :day))
      |> Padocs.SqliteRepo.update!()

      conn =
        post(conn, ~p"/sign-in", %{
          "user" => %{"email" => user.email, "password" => Fixtures.password()}
        })

      assert redirected_to(conn) == ~p"/reset"
      refute get_session(conn, :user_token)
    end

    test "a reset link sets a new password, confirms the account and signs in", %{conn: conn} do
      user = Fixtures.register_user()
      conn = post(conn, ~p"/reset", %{"user" => %{"email" => user.email}})
      assert redirected_to(conn) == ~p"/sign-in"

      token = link_token("/password-reset")
      assert html_response(get(build_conn(), ~p"/password-reset/#{token}"), 200)

      # The document sockets of the sessions signed out are closed.
      _session = build_conn() |> Fixtures.log_in(user)
      PadocsWeb.Endpoint.subscribe("user_socket:#{user.id}")

      conn =
        post(build_conn(), ~p"/password-reset/#{token}", %{
          "user" => %{"password" => "a-new-password", "password_confirmation" => "a-new-password"}
        })

      assert signed_in_user(conn).confirmed_at
      assert Accounts.get_user_by_email_and_password(user.email, "a-new-password")
      refute Accounts.get_user_by_email_and_password(user.email, Fixtures.password())
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end
  end

  describe "magic link" do
    test "registers an unknown address, confirmed when the link is used, once", %{conn: conn} do
      post(conn, ~p"/magic-link", %{"user" => %{"email" => "magic@example.com"}})
      token = link_token("/magic_link")

      # Following the link only shows a button: mail scanners open links.
      assert html_response(get(build_conn(), ~p"/magic_link/#{token}"), 200) =~
               "magic@example.com"

      refute Accounts.get_user_by_email("magic@example.com").confirmed_at

      conn = post(build_conn(), ~p"/magic_link/#{token}")
      assert %{email: "magic@example.com", confirmed_at: %DateTime{}} = signed_in_user(conn)

      conn = post(build_conn(), ~p"/magic_link/#{token}")
      assert redirected_to(conn) == ~p"/sign-in"
      refute get_session(conn, :user_token)
    end

    # Whoever chose its password may not own the address.
    test "refuses an unconfirmed account with a password", %{conn: conn} do
      user = Fixtures.register_user()
      _confirmation = link_token("/confirm_new_user")

      post(conn, ~p"/magic-link", %{"user" => %{"email" => user.email}})
      conn = post(build_conn(), ~p"/magic_link/#{link_token("/magic_link")}")

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "n'avez pas confirmé votre compte"
    end
  end

  test "signing out deletes the session token", %{conn: conn} do
    user = Fixtures.register_user()
    conn = conn |> Fixtures.log_in(user) |> delete(~p"/sign-out")

    assert redirected_to(conn) == ~p"/"
    refute get_session(conn, :user_token)

    assert Padocs.SqliteRepo.all_by(Accounts.UserToken, user_id: user.id, context: "session") ==
             []
  end

  test "a signed-in user is sent away from the sign-in page", %{conn: conn} do
    conn = conn |> Fixtures.log_in(Fixtures.register_user()) |> get(~p"/sign-in")
    assert redirected_to(conn) == ~p"/"
  end
end
