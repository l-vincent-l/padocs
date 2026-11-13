defmodule PadocsWeb.LocaleTest do
  use PadocsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Padocs.{Accounts, Fixtures}
  alias PadocsWeb.Locale

  describe "accepted/1" do
    test "the browser's first language we have, by weight" do
      assert Locale.accepted(["en-GB,en;q=0.9,fr;q=0.8"]) == "en"
      assert Locale.accepted(["de-DE,de;q=0.9,fr;q=0.7,en;q=0.5"]) == "fr"
      assert Locale.accepted(["fr;q=0.4, en;q=0.6"]) == "en"
      assert Locale.accepted(["FR-ca"]) == "fr"
    end

    test "none we have" do
      assert Locale.accepted(["de, es;q=0.5"]) == nil
      assert Locale.accepted(["en;q=0"]) == nil
      assert Locale.accepted([]) == nil
      assert Locale.accepted([""]) == nil
    end
  end

  describe "the language of a page" do
    test "French by default", %{conn: conn} do
      html = conn |> get(~p"/sign-in") |> html_response(200)
      assert html =~ ~r(<html[^>]* lang="fr")
      assert html =~ "Se connecter"
    end

    test "the browser's", %{conn: conn} do
      html =
        conn
        |> put_req_header("accept-language", "en-US,en;q=0.9")
        |> get(~p"/sign-in")
        |> html_response(200)

      assert html =~ ~r(<html[^>]* lang="en")
      assert html =~ "Sign in"
    end

    test "the user's choice before the browser's", %{conn: conn} do
      user = Fixtures.confirmed_user()
      {:ok, user} = Accounts.put_user_locale(user, "en")
      document = Fixtures.create_document!(user, %{title: "Notes"})

      {:ok, view, _html} =
        conn
        |> put_req_header("accept-language", "fr")
        |> Fixtures.log_in(user)
        |> live(~p"/documents/#{document.id}")

      assert has_element?(view, "#last-update", "Last update")
    end
  end

  describe "changing it" do
    test "kept in the session, back to the page", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "http://www.example.com/sign-in?x=1")
        |> post(~p"/locale", %{"locale" => "en"})

      assert redirected_to(conn) == "/sign-in?x=1"
      assert get_session(conn, "locale") == "en"

      html = conn |> recycle() |> get(~p"/sign-in") |> html_response(200)
      assert html =~ ~r(<html[^>]* lang="en")
    end

    test "on the account of a signed-in user", %{conn: conn} do
      user = Fixtures.confirmed_user()
      conn |> Fixtures.log_in(user) |> post(~p"/locale", %{"locale" => "en"})

      assert Padocs.SqliteRepo.get!(Accounts.User, user.id).locale == "en"
    end

    test "an unknown language, or another site's page, is ignored", %{conn: conn} do
      conn =
        conn
        |> put_req_header("referer", "https://elsewhere.example/page")
        |> post(~p"/locale", %{"locale" => "de"})

      assert redirected_to(conn) == ~p"/documents"
      refute get_session(conn, "locale") == "de"
    end
  end

  describe "emails" do
    test "in the user's language, else the current one" do
      user = Fixtures.confirmed_user()

      {:ok, email} = Accounts.UserNotifier.deliver_login_instructions(user, "https://x/link")
      assert email.subject == "Votre lien de connexion"

      {:ok, user} = Accounts.put_user_locale(user, "en")
      {:ok, email} = Accounts.UserNotifier.deliver_login_instructions(user, "https://x/link")
      assert email.subject == "Your sign-in link"
      assert email.html_body =~ "Click this link to sign in"
    end
  end
end
