defmodule PadocsWeb.PreferencesLiveTest do
  use PadocsWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Padocs.{Accounts, Fixtures}

  setup %{conn: conn} do
    user = Fixtures.confirmed_user()
    %{conn: Fixtures.log_in(conn, user), user: user}
  end

  test "signed out, back to signing in" do
    assert {:error, {:redirect, %{to: "/sign-in"}}} = live(build_conn(), ~p"/preferences")
  end

  test "the language, the theme and the account", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/preferences")

    assert has_element?(view, "#language-form[action='/locale'][method=post]")
    assert has_element?(view, "#language-fr[aria-pressed=true]")
    assert has_element?(view, "#language-en[aria-pressed=false]")

    for theme <- ["system", "light", "dark"] do
      assert has_element?(view, "#theme-#{theme}[data-phx-theme=#{theme}]")
    end

    assert has_element?(view, "#account-email", user.email)
    assert has_element?(view, "#sign-out[data-method=delete][href='/sign-out']")
  end

  test "the language chosen is marked, and kept on the account", %{conn: conn, user: user} do
    conn =
      conn
      |> put_req_header("referer", "http://www.example.com/preferences")
      |> post(~p"/locale", %{"locale" => "en"})

    assert redirected_to(conn) == ~p"/preferences"
    assert Padocs.SqliteRepo.get!(Accounts.User, user.id).locale == "en"

    {:ok, view, _html} = conn |> recycle() |> live(~p"/preferences")
    assert has_element?(view, "#language-en[aria-pressed=true]")
    assert has_element?(view, "h1", "Preferences")
  end

  test "the sidebar of a document leads there", %{conn: conn, user: user} do
    document = Fixtures.create_document!(user, %{title: "Notes"})
    {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

    assert has_element?(view, "#account #preferences-link[href='/preferences']", user.email)
  end
end
