defmodule TextexpWeb.PublicDocumentLiveTest do
  use TextexpWeb.ConnCase

  alias Textexp.Fixtures

  import Phoenix.LiveViewTest

  alias Textexp.Document

  defp register_user, do: Fixtures.confirmed_user()

  setup do
    owner = register_user()
    document = Fixtures.create_document!(owner, %{title: "Compte rendu"})
    {:ok, token} = Document.enable_public_link(owner, document.id)
    %{owner: owner, document: document, token: token}
  end

  test "anyone reads the document, read-only, with the token", %{
    conn: conn,
    document: document,
    token: token
  } do
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")

    assert has_element?(view, "#public-title", "Compte rendu")
    assert has_element?(view, "#public-badge")

    assert has_element?(
             view,
             ~s(#public-editor-#{document.id}[phx-hook="DocumentEditor"][data-editable="false"][data-public-token="#{token}"])
           )

    # nothing of the signed-in page
    refute has_element?(view, "#share-button")
    refute has_element?(view, "#documents")
  end

  test "an unknown token leads nowhere", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/p/unknown")

    assert has_element?(view, "#public-unavailable")
    assert has_element?(view, "#public-sign-in")
    refute has_element?(view, "#public-document")
  end

  test "a signed-in user who can read it goes to its page", %{
    conn: conn,
    owner: owner,
    document: document,
    token: token
  } do
    conn = Fixtures.log_in(conn, owner)
    path = ~p"/documents/#{document.id}"

    assert {:error, {:live_redirect, %{to: ^path}}} = live(conn, ~p"/p/#{token}")
  end

  test "a signed-in user without access reads it publicly", %{conn: conn, token: token} do
    conn = Fixtures.log_in(conn, register_user())
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")

    assert has_element?(view, "#public-document")
    refute has_element?(view, "#public-sign-in")
  end

  test "a link removed or replaced while open closes the page", %{
    conn: conn,
    owner: owner,
    document: document,
    token: token
  } do
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")
    :ok = Document.disable_public_link(owner, document.id)
    assert has_element?(view, "#public-unavailable")

    {:ok, token} = Document.enable_public_link(owner, document.id)
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")
    {:ok, _new} = Document.enable_public_link(owner, document.id)
    assert has_element?(view, "#public-unavailable")
  end

  test "a document put in the trash closes the page", %{
    conn: conn,
    owner: owner,
    document: document,
    token: token
  } do
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")
    :ok = Document.trash_document(document.id, owner)

    assert has_element?(view, "#public-unavailable")
  end

  test "a rename shows at once", %{conn: conn, owner: owner, document: document, token: token} do
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")
    {:ok, _} = Document.rename_document(document, owner, "Nouveau titre")

    assert has_element?(view, "#public-title", "Nouveau titre")
  end

  test "the comments' authors are named without their address", %{
    conn: conn,
    owner: owner,
    token: token
  } do
    {:ok, view, _html} = live(conn, ~p"/p/#{token}")
    render_hook(view, "resolve_users", %{"ids" => [owner.id]})

    assert_reply(view, %{users: [%{id: id, username: "Membre"}]})
    assert id == owner.id
  end
end
