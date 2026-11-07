defmodule TextexpWeb.DocumentLiveTest do
  use TextexpWeb.ConnCase

  alias Textexp.Fixtures

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Textexp.Document

  defp register_user, do: Fixtures.confirmed_user()

  defp log_in(conn, user), do: Fixtures.log_in(conn, user)

  describe "signed in" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
    end

    test "renaming updates the document and the sidebar", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      editor = "#document-editor-#{document.id}[phx-hook='DocumentEditor']"
      assert has_element?(view, "#{editor}[data-document-id='#{document.id}']")
      assert has_element?(view, "#documents-link[href='/documents']")
      assert has_element?(view, "#search-button")
      assert has_element?(view, "#{editor} [data-skeleton]")
      assert has_element?(view, "#{editor} [data-editor][hidden]")

      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})

      assert Document.get_document!(document.id).title == "Mon document"
      assert has_element?(view, "#documents-#{document.id}", "Mon document")
    end

    test "shows content updates of the open document", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, ~U[2030-01-02 03:04:05.000000Z], nil}
      )

      assert has_element?(view, "#last-update", "02/01/2030 03:04:05")
    end

    test "shows the title given by a save to an untitled document",
         %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, DateTime.utc_now(), "Note du 01-02-2030"}
      )

      assert has_element?(view, "#document-title[value='Note du 01-02-2030']")
      assert has_element?(view, "#documents-#{document.id}", "Note du 01-02-2030")
      assert page_title(view) =~ "Note du 01-02-2030"
    end

    test "a save does not replace the title being typed", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      view |> element("#title-form") |> render_change(%{"title" => "Mon titre"})

      # saved before the title was typed
      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.topic(document.id),
        {:document_updated, document.id, DateTime.utc_now(), "Note du 01-02-2030"}
      )

      assert has_element?(view, "#document-title[value='Mon titre']")
    end

    test "lists the people viewing the document", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      other = register_user()
      Fixtures.share!(user, document, other, :viewer)

      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      {:ok, other_view, _html} = live(log_in(build_conn(), other), ~p"/documents/#{document.id}")

      assert has_element?(view, "#viewers-#{user.id}")
      assert has_element?(view, "#viewers-#{other.id}")

      # the leave is handled asynchronously by the Presence tracker
      TextexpWeb.Presence.subscribe("viewers:#{document.id}")
      other_id = other.id
      GenServer.stop(other_view.pid)
      assert_receive {TextexpWeb.Presence, {:leave, %{id: ^other_id}}}

      refute has_element?(view, "#viewers-#{other.id}")
    end

    test "the open document being deleted redirects to the list", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, document.id}
      )

      assert_redirect(view, ~p"/documents")
    end

    test "a deleted empty document leaves the sidebar", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{title: "Notes"})
      {:ok, other} = Document.create_sub_document(document.id, user)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      assert has_element?(view, "#documents-#{other.id}")

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        Textexp.Document.YPersistence.documents_topic(),
        {:document_deleted, other.id}
      )

      refute has_element?(view, "#documents-#{other.id}")
    end

    test "creating a document from the sidebar opens it", %{conn: conn, user: user} do
      document = Fixtures.create_document!(user, %{title: "Notes"})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#new-document") |> render_click()
      assert "/documents/" <> id = assert_patch(view)

      assert has_element?(view, "#document-editor-#{id}")
      assert has_element?(view, "#documents-#{id} > div.menu-active")
    end

    test "switching documents moves the editor, the active item and the viewer",
         %{conn: conn, user: user} do
      first = Fixtures.create_document!(user, %{title: "First"})
      second = Fixtures.create_document!(user, %{title: "Second"})
      {:ok, view, _html} = live(conn, ~p"/documents/#{first.id}")
      assert [_] = TextexpWeb.Presence.list_users("viewers:#{first.id}")

      render_patch(view, ~p"/documents/#{second.id}")

      assert has_element?(view, "#document-editor-#{second.id}")
      refute has_element?(view, "#document-editor-#{first.id}")
      assert has_element?(view, "#documents-#{second.id} > div.menu-active")
      refute has_element?(view, "#documents-#{first.id}")
      assert has_element?(view, "#viewers-#{user.id}")
      assert TextexpWeb.Presence.list_users("viewers:#{first.id}") == []
    end

    test "an unknown document redirects to the list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               live(conn, ~p"/documents/#{Ecto.UUID.generate()}")
    end

    test "another user's document redirects to the list", %{conn: conn} do
      document = Fixtures.create_document!(register_user(), %{title: "Notes"})

      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               live(conn, ~p"/documents/#{document.id}")
    end

    test "an editor renames the document", %{conn: conn, user: user} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      Fixtures.share!(owner, document, user, :editor)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-editor-#{document.id}[data-editable='true']")
      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})

      assert Document.get_document!(document.id).title == "Mon document"
    end

    test "a rename shows on the other pages of the document", %{conn: conn, user: user} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      Fixtures.share!(owner, document, user, :viewer)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      {:ok, owner_view, _html} = live(log_in(build_conn(), owner), ~p"/documents/#{document.id}")

      owner_view |> element("#title-form") |> render_change(%{"title" => "Mon document"})

      assert has_element?(view, "#document-title[value='Mon document']")
      assert has_element?(view, "#documents-#{document.id}", "Mon document")
      assert page_title(view) =~ "Mon document"
    end

    test "a viewer reads the document without editing it", %{conn: conn, user: user} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      Fixtures.share!(owner, document, user, :viewer)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      assert has_element?(view, "#document-title[readonly]")
      assert has_element?(view, "#document-editor-#{document.id}[data-editable='false']")

      view |> element("#title-form") |> render_change(%{"title" => "Mon document"})
      assert Document.get_document!(document.id).title == "Notes"
    end
  end

  describe "sharing" do
    setup %{conn: conn} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      %{conn: log_in(conn, owner), owner: owner, document: document}
    end

    test "the owner invites an address as editor", %{conn: conn, document: document} do
      editor = register_user()
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      refute has_element?(view, "#share-panel")
      view |> element("#share-button") |> render_click()
      assert has_element?(view, "#members-empty")

      view
      |> form("#share-form", share: %{email: editor.email, role: "editor"})
      |> render_submit()

      assert has_element?(view, "#members li", to_string(editor.email))
      assert has_element?(view, "#members li", "Éditeur")

      assert {:ok, %{role: :editor}} = Document.get_document(document.id, editor)
    end

    test "an address without account is refused", %{conn: conn, document: document} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      view |> element("#share-button") |> render_click()

      html =
        view
        |> form("#share-form", share: %{email: "nobody@example.com", role: "viewer"})
        |> render_submit()

      assert html =~ "aucun compte avec cette adresse"
      assert has_element?(view, "#members-empty")
    end

    test "the owner removes a member", %{conn: conn, owner: owner, document: document} do
      viewer = register_user()
      membership = Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#share-button") |> render_click()
      assert has_element?(view, "#members-#{membership.id}", "Lecteur")

      view |> element("#remove-#{membership.id}") |> render_click()

      refute has_element?(view, "#members-#{membership.id}")
      assert {:error, _} = Document.get_document(document.id, viewer)
    end

    test "the search modal finds documents by their text", %{
      conn: conn,
      owner: owner,
      document: document
    } do
      other = Fixtures.create_document!(owner, %{title: "Recette de la tarte"})
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#search-button") |> render_click()
      assert has_element?(view, "#search-panel[role=dialog]")

      view |> form("#search-modal-form", search: %{query: "tarte"}) |> render_change()
      # The index is built in the background
      assert render_async(view, 2_000) =~ "Recette de la tarte"
      assert has_element?(view, "#search-results a[href='/documents/#{other.id}']")

      # Closing it ends the process holding the index, which frees it
      index = :sys.get_state(view.pid).socket.assigns.search_index
      ref = Process.monitor(index)

      view |> element("#search-close") |> render_click()
      refute has_element?(view, "#search-panel")
      assert_receive {:DOWN, ^ref, :process, ^index, :shutdown}
    end

    test "the share modal closes with its button and Escape", %{conn: conn, document: document} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#share-button") |> render_click()
      assert has_element?(view, "#share-modal[class~=modal-open] #share-panel[role=dialog]")

      view |> element("#share-close") |> render_click()
      refute has_element?(view, "#share-modal")

      view |> element("#share-button") |> render_click()
      view |> element("#share-modal") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#share-modal")
    end

    test "the owner switches a member between viewer and editor",
         %{conn: conn, owner: owner, document: document} do
      member = register_user()
      membership = Fixtures.share!(owner, document, member, :viewer)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      view |> element("#share-button") |> render_click()

      view
      |> form("#role-#{membership.id}", member: %{role: "editor"})
      |> render_change()

      assert has_element?(view, "#role-#{membership.id} option[selected][value=editor]")
      assert {:ok, %{role: :editor}} = Document.get_document(document.id, member)

      view
      |> form("#role-#{membership.id}", member: %{role: "viewer"})
      |> render_change()

      assert has_element?(view, "#role-#{membership.id} option[selected][value=viewer]")
      assert {:ok, %{role: :viewer}} = Document.get_document(document.id, member)
    end

    test "a member removed is sent back to the list", %{owner: owner, document: document} do
      viewer = register_user()
      membership = Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, view, _html} = live(log_in(build_conn(), viewer), ~p"/documents/#{document.id}")

      :ok = Document.remove_member(owner, membership.id)

      assert_redirect(view, ~p"/documents")
    end

    test "a member whose role changes gets the page again", %{owner: owner, document: document} do
      member = register_user()
      Fixtures.share!(owner, document, member, :viewer)
      {:ok, view, _html} = live(log_in(build_conn(), member), ~p"/documents/#{document.id}")

      Fixtures.share!(owner, document, member, :editor)

      assert_redirect(view, ~p"/documents/#{document.id}")
    end

    test "members do not see the share button", %{owner: owner, document: document} do
      editor = register_user()
      Fixtures.share!(owner, document, editor, :editor)
      {:ok, view, _html} = live(log_in(build_conn(), editor), ~p"/documents/#{document.id}")

      refute has_element?(view, "#share-button")
    end
  end

  describe "/documents" do
    setup %{conn: conn} do
      user = register_user()
      %{conn: log_in(conn, user), user: user}
    end

    defp opened_at_documents(conn) do
      assert {:error, {_redirect, %{to: "/documents/" <> id}}} = live(conn, ~p"/documents")
      id
    end

    test "opens the document opened last", %{conn: conn, user: user} do
      first = Fixtures.create_document!(user, %{title: "First"})
      _last_updated = Fixtures.create_document!(user, %{title: "Last updated"})
      {:ok, _view, _html} = live(conn, ~p"/documents/#{first.id}")

      assert opened_at_documents(conn) == first.id
    end

    test "without one, opens the document updated last", %{conn: conn, user: user} do
      older = Fixtures.create_document!(user, %{title: "Older"})
      _newer = Fixtures.create_document!(user, %{title: "Newer"})
      Document.save_snapshot(older.id, nil, "edited")

      assert opened_at_documents(conn) == older.id
    end

    test "skips a document opened last that can no longer be read", %{conn: conn, user: user} do
      owner = register_user()
      shared = Fixtures.create_document!(owner, %{title: "Shared"})
      membership = Fixtures.share!(owner, shared, user, :viewer)
      own = Fixtures.create_document!(user, %{title: "Mine"})
      {:ok, view, _html} = live(conn, ~p"/documents/#{shared.id}")
      :ok = Document.remove_member(owner, membership.id)
      assert_redirect(view, ~p"/documents")

      assert opened_at_documents(conn) == own.id
    end

    test "without any document, creates one", %{conn: conn, user: user} do
      id = opened_at_documents(conn)

      assert %{owner_id: owner_id, title: nil} = Document.get_document!(id)
      assert owner_id == user.id
    end

    test "the sidebar shows the open document and its sub-documents only",
         %{conn: conn, user: user} do
      other = register_user()
      own = Fixtures.create_document!(user, %{title: "Mine"})
      {:ok, child} = Document.create_sub_document(own.id, user)
      {:ok, grandchild} = Document.create_sub_document(child.id, user)
      sibling = Fixtures.create_document!(user, %{title: "Another"})
      shared = Fixtures.create_document!(other, %{title: "Shared"})
      Fixtures.share!(other, shared, user, :viewer)

      {:ok, view, _html} = live(conn, ~p"/documents/#{own.id}")

      assert has_element?(view, "#documents > #documents-#{own.id} > div.menu-active")
      assert has_element?(view, "#documents-#{own.id} #documents-#{child.id}")
      refute has_element?(view, "#documents-#{grandchild.id}")
      refute has_element?(view, "#documents-#{sibling.id}")
      refute has_element?(view, "#documents-#{shared.id}")

      # a sub-document, opened, is the sidebar's first level
      render_patch(view, ~p"/documents/#{child.id}")
      assert has_element?(view, "#documents > #documents-#{child.id}")
      assert has_element?(view, "#documents-#{child.id} #documents-#{grandchild.id}")
      refute has_element?(view, "#documents-#{own.id}")
    end
  end

  describe "sidebar" do
    test "can be folded and resized, by the Sidebar hook", %{conn: conn} do
      owner = register_user()
      document = Fixtures.create_document!(owner)
      {:ok, view, _html} = live(log_in(conn, owner), ~p"/documents/#{document.id}")

      assert has_element?(view, "#app-drawer[phx-hook]")
      assert has_element?(view, "#sidebar-collapse[data-sidebar-toggle]")
      assert has_element?(view, "#sidebar-expand[data-sidebar-toggle]")
      assert has_element?(view, ~s(#app-drawer > #sidebar-resize[role="separator"]))
    end
  end

  describe "sub-documents" do
    setup %{conn: conn} do
      owner = register_user()
      parent = Fixtures.create_document!(owner, %{title: "Projet"})
      %{conn: log_in(conn, owner), owner: owner, parent: parent}
    end

    test "an editor creates one from the sidebar, opened under its parent",
         %{conn: conn, parent: parent} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{parent.id}")

      view |> element("#documents-#{parent.id}-new") |> render_click()

      [child] =
        Textexp.SqliteRepo.all(from d in Document.Document, where: d.parent_id == ^parent.id)

      assert_patch(view, ~p"/documents/#{child.id}")

      assert has_element?(view, "#documents > #documents-#{child.id} > div.menu-active")
      assert has_element?(view, "#breadcrumb-#{parent.id}", "Projet")
    end

    test "the sub-documents of a sub-document unfold on demand",
         %{conn: conn, owner: owner, parent: parent} do
      {:ok, child} = Document.create_sub_document(parent.id, owner)
      {:ok, grandchild} = Document.create_sub_document(child.id, owner)
      {:ok, view, _html} = live(conn, ~p"/documents/#{parent.id}")

      assert has_element?(view, "#documents-#{parent.id} #documents-#{child.id}")
      refute has_element?(view, "#documents-#{grandchild.id}")

      view |> element("#documents-#{child.id}-toggle") |> render_click()
      assert has_element?(view, "#documents-#{child.id} #documents-#{grandchild.id}")

      view |> element("#documents-#{child.id}-toggle") |> render_click()
      refute has_element?(view, "#documents-#{grandchild.id}")
    end

    test "a sub-document shows its parents in the breadcrumb",
         %{conn: conn, owner: owner, parent: parent} do
      {:ok, child} = Document.create_sub_document(parent.id, owner)
      {:ok, grandchild} = Document.create_sub_document(child.id, owner)

      {:ok, view, _html} = live(conn, ~p"/documents/#{grandchild.id}")

      assert has_element?(view, "#breadcrumb-#{parent.id}")
      assert has_element?(view, "#breadcrumb-#{child.id}")
      refute has_element?(view, "#documents-#{parent.id}")
    end

    test "a viewer sees the sub-documents, without creating any",
         %{owner: owner, parent: parent} do
      {:ok, child} = Document.create_sub_document(parent.id, owner)
      viewer = register_user()
      Fixtures.share!(owner, parent, viewer, :viewer)

      {:ok, view, _html} = live(log_in(build_conn(), viewer), ~p"/documents/#{parent.id}")

      assert has_element?(view, "#documents-#{parent.id} #documents-#{child.id}")
      refute has_element?(view, "#documents-#{parent.id}-new")
      refute has_element?(view, ~s(#documents-#{child.id} > div[draggable="true"]))
      refute has_element?(view, "#document-actions")
    end
  end

  describe "inherited accesses" do
    setup %{conn: conn} do
      owner = register_user()
      parent = Fixtures.create_document!(owner, %{title: "Projet"})
      {:ok, child} = Document.create_sub_document(parent.id, owner)
      %{conn: log_in(conn, owner), owner: owner, parent: parent, child: child}
    end

    test "the share panel lists those of the parents, apart from the members",
         %{conn: conn, owner: owner, parent: parent, child: child} do
      inherited = register_user()
      Fixtures.share!(owner, parent, inherited, :editor)
      direct = register_user()
      Fixtures.share!(owner, child, direct, :viewer)

      {:ok, view, _html} = live(conn, ~p"/documents/#{child.id}")
      view |> element("#share-button") |> render_click()

      assert has_element?(view, "#members", direct.email)
      refute has_element?(view, "#members", inherited.email)
      assert has_element?(view, "#inherited-#{inherited.id}", "Éditeur")
      assert has_element?(view, "#inherited-#{inherited.id}-from", "Projet")
      refute has_element?(view, "#inherited-#{direct.id}")

      view |> element("#inherited-#{inherited.id}-from") |> render_click()
      assert_patch(view, ~p"/documents/#{parent.id}")
    end

    test "a document without parent has none", %{conn: conn, parent: parent} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{parent.id}")
      view |> element("#share-button") |> render_click()

      refute has_element?(view, "#inherited-accesses")
    end
  end

  describe "moving documents" do
    setup %{conn: conn} do
      owner = register_user()
      parent = Fixtures.create_document!(owner, %{title: "Projet"})
      {:ok, child} = Document.create_sub_document(parent.id, owner)
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      %{conn: log_in(conn, owner), owner: owner, parent: parent, child: child, other: other}
    end

    test "a sub-document dropped onto another goes under it, unfolded",
         %{conn: conn, owner: owner, parent: parent, child: child} do
      {:ok, sibling} = Document.create_sub_document(parent.id, owner)
      {:ok, view, _html} = live(conn, ~p"/documents/#{parent.id}")
      assert has_element?(view, ~s(#documents-#{child.id} > div[draggable="true"]))

      view
      |> element("#documents-tree")
      |> render_hook("move_document", %{"id" => child.id, "parent_id" => sibling.id})

      assert has_element?(view, "#documents-#{sibling.id} #documents-#{child.id}")
      assert {:ok, %{parent_id: parent_id}} = Document.get_document(child.id, owner)
      assert parent_id == sibling.id
    end

    test "a document dropped onto the root leaves its parent",
         %{conn: conn, owner: owner, parent: parent, child: child} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{parent.id}")

      view
      |> element("#documents-tree")
      |> render_hook("move_document", %{"id" => child.id, "parent_id" => nil})

      # no longer a sub-document of the open document
      refute has_element?(view, "#documents-#{child.id}")
      assert {:ok, %{parent_id: nil}} = Document.get_document(child.id, owner)
    end

    test "a document cannot go under one of its descendants",
         %{conn: conn, parent: parent, child: child} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{parent.id}")

      view
      |> element("#documents-tree")
      |> render_hook("move_document", %{"id" => parent.id, "parent_id" => child.id})

      assert has_element?(view, "#documents > #documents-#{parent.id}")
      assert has_element?(view, "#flash-error")
    end

    test "the move panel moves the open document, the breadcrumb following",
         %{conn: conn, parent: parent, child: child, other: other} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{child.id}")
      assert has_element?(view, "#breadcrumb-#{parent.id}")

      view |> element("#move-button") |> render_click()
      # neither its parent nor itself
      refute has_element?(view, "#move-to-#{parent.id}")
      refute has_element?(view, "#move-to-#{child.id}")
      assert has_element?(view, "#move-to-root")

      view |> element("#move-to-#{other.id}") |> render_click()

      refute has_element?(view, "#move-panel")
      assert has_element?(view, "#breadcrumb-#{other.id}")
      refute has_element?(view, "#breadcrumb-#{parent.id}")
      assert has_element?(view, "#documents > #documents-#{child.id}")
    end

    test "the move panel moves the open document to the root",
         %{conn: conn, parent: parent, child: child} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{child.id}")

      view |> element("#move-button") |> render_click()
      view |> element("#move-to-root") |> render_click()

      refute has_element?(view, "#breadcrumb")
      refute has_element?(view, "#documents-#{parent.id} #documents-#{child.id}")
    end

    test "a move on another page shows in the sidebar",
         %{conn: conn, owner: owner, child: child, other: other} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{other.id}")

      {:ok, _} = Document.move_document(child.id, other.id, owner)

      # the open document is unfolded
      _ = render(view)
      assert has_element?(view, "#documents-#{other.id} #documents-#{child.id}")
    end
  end

  describe "tags" do
    setup %{conn: conn} do
      owner = register_user()
      document = Fixtures.create_document!(owner, %{title: "Notes"})
      {:ok, view, _html} = live(log_in(conn, owner), ~p"/documents/#{document.id}")
      %{owner: owner, document: document, view: view}
    end

    defp add_tag(view, label) do
      view |> element("#add-tag") |> render_click()
      view |> form("#tag-form", %{"label" => label}) |> render_submit()
    end

    test "an editor adds a tag", %{document: document, view: view} do
      add_tag(view, "Urgent")

      assert [%{id: id, label: "Urgent"}] = Document.list_tags(document.id)
      assert has_element?(view, "#tags-#{id}", "Urgent")
      refute has_element?(view, "#tag-form")
    end

    test "the field suggests the tags of the user's other documents",
         %{owner: owner, document: document, view: view} do
      other = Fixtures.create_document!(owner, %{title: "Other"})
      {:ok, _} = Document.add_tag(other.id, owner, "Recettes")
      {:ok, _} = Document.add_tag(document.id, owner, "Urgent")

      view |> element("#add-tag") |> render_click()

      assert has_element?(view, "#tag-suggestions option[value='Recettes']")
      refute has_element?(view, "#tag-suggestions option[value='Urgent']")
    end

    test "an editor removes a tag", %{owner: owner, document: document, view: view} do
      {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")
      assert has_element?(view, "#tags-#{tag.id}")

      view |> element("#tags-#{tag.id} button[phx-click=remove_tag]") |> render_click()

      assert Document.list_tags(document.id) == []
      refute has_element?(view, "#tags-#{tag.id}")
    end

    test "a tag opens the search on the documents carrying it",
         %{owner: owner, document: document, view: view} do
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      untagged = Fixtures.create_document!(owner, %{title: "Sans tag"})
      {:ok, tag} = Document.add_tag(document.id, owner, "Recettes")
      {:ok, _} = Document.add_tag(other.id, owner, "Recettes")

      view |> element("#tags-#{tag.id} button[phx-click=search_tag]") |> render_click()

      assert has_element?(view, "#search-panel #search-active-tag", "Recettes")
      assert has_element?(view, "#search-results a[href='/documents/#{document.id}']")
      assert has_element?(view, "#search-results a[href='/documents/#{other.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{untagged.id}']")
    end

    test "a viewer sees the tags without changing them",
         %{conn: conn, owner: owner, document: document} do
      viewer = register_user()
      Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")
      {:ok, view, _html} = live(log_in(conn, viewer), ~p"/documents/#{document.id}")

      assert has_element?(view, "#tags-#{tag.id}", "Urgent")
      refute has_element?(view, "#tags-#{tag.id} button[phx-click=remove_tag]")
      refute has_element?(view, "#add-tag")
    end

    test "tags changed on another page show here", %{owner: owner, document: document} do
      {:ok, other_view, _html} = live(log_in(build_conn(), owner), ~p"/documents/#{document.id}")

      {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")

      assert has_element?(other_view, "#tags-#{tag.id}", "Urgent")
    end
  end

  describe "import" do
    setup %{conn: conn} do
      user = register_user()
      document = Fixtures.create_document!(user, %{title: "Notes"})
      {:ok, view, _html} = live(log_in(conn, user), ~p"/documents/#{document.id}")
      %{user: user, view: view}
    end

    # The Yjs state the DocumentImport hook sends for a file holding `text`.
    defp import_state(text), do: text |> state() |> Base.encode64()

    test "the sidebar offers a file input to the hook", %{view: view} do
      assert has_element?(
               view,
               "#import-document input#import-files[type=file][phx-hook=DocumentImport]"
             )
    end

    test "creates a document from a converted file", %{user: user, view: view} do
      render_hook(view, "import_document", %{
        "name" => "Recette des crêpes.md",
        "state" => import_state("Farine, œufs, lait")
      })

      assert_reply(view, %{id: id})

      document = Document.get_document!(id)
      assert document.owner_id == user.id
      assert document.title == "Recette des crêpes"
      assert Document.markdown(document) == "Farine, œufs, lait"
    end

    test "reports a file it could not import", %{view: view} do
      html = render_hook(view, "import_document", %{"name" => "x.md", "state" => "not base64!"})
      assert_reply(view, %{})
      assert html =~ "Impossible d&#39;importer « x.md »"

      html = render_hook(view, "import_failed", %{"name" => "big.md", "reason" => "too_large"})
      assert html =~ "trop volumineux"
    end
  end

  describe "search modal" do
    setup %{conn: conn} do
      user = register_user()
      document = Fixtures.create_document!(user, %{title: "Notes"})
      {:ok, view, _html} = live(log_in(conn, user), ~p"/documents/#{document.id}")
      %{user: user, view: view}
    end

    # Opens the modal, which indexes the documents as they are then, and searches.
    defp search(view, query) do
      view |> element("#search-button") |> render_click()
      view |> form("#search-modal-form", search: %{query: query}) |> render_change()
      # Searches run in the background, the first one waiting for the index
      render_async(view, 2_000)
    end

    test "results show where the words appear in the body", %{user: user, view: view} do
      document = Fixtures.create_document!(user, %{title: "Chez moi"})
      Document.save_snapshot(document.id, state("Le chat dort"), "Le chat dort")

      search(view, "chat")

      assert has_element?(view, "#search-results [role=option] p mark", "chat")
    end

    test "ignores the documents the user cannot read", %{user: user, view: view} do
      own = Fixtures.create_document!(user, %{title: "Mes chats"})
      hidden = Fixtures.create_document!(register_user(), %{title: "Leurs chats"})

      search(view, "chats")

      assert has_element?(view, "#search-results a[href='/documents/#{own.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{hidden.id}']")
    end

    test "a picked tag filters the results", %{user: user, view: view} do
      tagged = Fixtures.create_document!(user, %{title: "Crêpes"})
      other = Fixtures.create_document!(user, %{title: "Gaufres"})
      stranger = register_user()
      hidden = Fixtures.create_document!(stranger, %{title: "Leur recette"})
      {:ok, tag} = Document.add_tag(tagged.id, user, "Recettes")
      {:ok, _} = Document.add_tag(hidden.id, stranger, "Recettes cachées")

      search(view, "rec")
      assert has_element?(view, "#search-tag-#{tag.id}", "Recettes")
      refute has_element?(view, "#search-tags", "cachées")

      view |> element("#search-tag-#{tag.id}") |> render_click()

      assert has_element?(view, "#search-active-tag", "Recettes")
      refute has_element?(view, "#search-tags")
      assert has_element?(view, "#search-results a[href='/documents/#{tagged.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{other.id}']")

      view |> element("#search-clear-tag") |> render_click()

      refute has_element?(view, "#search-active-tag")
      # the empty field shows the lists again
      assert has_element?(view, "#search-lists")
    end

    test "with a tag picked, a query searches the documents carrying it",
         %{user: user, view: view} do
      tagged = Fixtures.create_document!(user, %{title: "Crêpes au sucre"})
      other = Fixtures.create_document!(user, %{title: "Gaufres au sucre"})
      {:ok, tag} = Document.add_tag(tagged.id, user, "Recettes")

      search(view, "rec")
      view |> element("#search-tag-#{tag.id}") |> render_click()
      view |> form("#search-modal-form", search: %{query: "sucre"}) |> render_change()
      render_async(view, 2_000)

      assert has_element?(view, "#search-results a[href='/documents/#{tagged.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{other.id}']")
    end

    test "the empty modal offers the 4 most searched tags, then all of them by label",
         %{user: user, view: view} do
      document = Fixtures.create_document!(user, %{title: "Tagué"})

      tags =
        for label <- ~w(Épices Arbre Bleu Ciel Dune Feu) do
          {:ok, tag} = Document.add_tag(document.id, user, label)
          tag
        end

      feu = Enum.find(tags, &(&1.label == "Feu"))
      Document.record_tag_search(user, feu.id)

      view |> element("#search-button") |> render_click()

      assert labels(view) == ["Feu", "Arbre", "Bleu", "Ciel"]
      assert has_element?(view, "#search-more-tags")

      view |> element("#search-more-tags") |> render_click()

      assert labels(view) == ["Arbre", "Bleu", "Ciel", "Dune", "Épices", "Feu"]
      refute has_element?(view, "#search-more-tags")
    end

    test "picking a tag counts as a search of it", %{user: user, view: view} do
      document = Fixtures.create_document!(user, %{title: "Tagué"})
      for label <- ~w(Arbre Bleu), do: Document.add_tag(document.id, user, label)
      {:ok, bleu} = Document.add_tag(document.id, user, "Bleu")

      view |> element("#search-button") |> render_click()
      refute has_element?(view, "#search-more-tags")
      view |> element("#search-tag-#{bleu.id}") |> render_click()

      assert [%{label: "Bleu"} | _] = Document.top_tags(user, 2)
    end

    # The labels of the tags offered under the field, in order.
    defp labels(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#search-tags [id^=search-tag-]")
      |> Enum.map(&LazyHTML.text/1)
      |> Enum.map(&String.trim/1)
    end

    test "a search without match shows that nothing was found", %{view: view} do
      search(view, "chats AND (")

      assert has_element?(view, "#search-results-empty", "Aucun résultat")
    end
  end

  # The Yjs state of a BlockNote document holding one paragraph of `text`.
  defp state(text) do
    doc = Yex.Doc.new()

    doc
    |> Yex.Doc.get_xml_fragment("document-store")
    |> Yex.XmlFragment.push(
      Yex.XmlElementPrelim.new("blockGroup", [
        Yex.XmlElementPrelim.new("blockContainer", [
          Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from(text)])
        ])
      ])
    )

    Yex.encode_state_as_update!(doc)
  end

  describe "lists of the search modal" do
    setup %{conn: conn} do
      user = register_user()
      open = Fixtures.create_document!(user, %{title: "Ouvert"})
      %{conn: log_in(conn, user), user: user, open: open}
    end

    defp open_search(conn, document) do
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      view |> element("#search-button") |> render_click()
      view
    end

    test "the empty field lists the recent documents, the last opened first",
         %{conn: conn, user: user, open: open} do
      older = Fixtures.create_document!(user, %{title: "Plus ancien"})
      never = Fixtures.create_document!(user, %{title: "Jamais ouvert"})
      Document.opened(user, older)

      view = open_search(conn, open)

      assert has_element?(view, ~s(#search-list-recent[aria-pressed="true"]))
      assert has_element?(view, "#search-results a[href='/documents/#{open.id}']")
      assert has_element?(view, "#search-results a[href='/documents/#{older.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{never.id}']")

      # a query replaces the lists
      view |> form("#search-modal-form", search: %{query: "jamais"}) |> render_change()
      refute has_element?(view, "#search-lists")
    end

    test "own and shared documents", %{conn: conn, user: user, open: open} do
      other = register_user()
      shared = Fixtures.create_document!(other, %{title: "Le leur"})
      Fixtures.share!(other, shared, user, :viewer)

      view = open_search(conn, open)

      view |> element("#search-list-own") |> render_click()
      assert has_element?(view, ~s(#search-list-own[aria-pressed="true"]))
      assert has_element?(view, "#search-results a[href='/documents/#{open.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{shared.id}']")

      view |> element("#search-list-shared") |> render_click()
      assert has_element?(view, "#search-results a[href='/documents/#{shared.id}']")
      refute has_element?(view, "#search-results a[href='/documents/#{open.id}']")
    end

    test "a document put in the trash is restored from there",
         %{conn: conn, user: user, open: open} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{open.id}")

      assert {:error, {:live_redirect, %{to: "/documents"}}} =
               view |> element("#trash-button") |> render_click()

      assert {:error, :not_found} = Document.get_document(open.id, user)

      other = Fixtures.create_document!(user, %{title: "Autre"})
      view = open_search(conn, other)
      view |> element("#search-list-trash") |> render_click()

      refute has_element?(view, "#search-results a[href='/documents/#{open.id}']")
      assert has_element?(view, "#restore-#{open.id}")

      view |> element("#restore-#{open.id}") |> render_click()

      refute has_element?(view, "#restore-#{open.id}")
      assert has_element?(view, "#flash-info", "restauré")
      assert {:ok, _} = Document.get_document(open.id, user)
      # back in the sidebar if under the open document: here, not shown
      refute has_element?(view, "#documents-#{open.id}")
    end

    test "the trash is emptied, or a document deleted for good",
         %{conn: conn, user: user, open: open} do
      first = Fixtures.create_document!(user, %{title: "Un"})
      second = Fixtures.create_document!(user, %{title: "Deux"})
      :ok = Document.trash_document(first.id, user)
      :ok = Document.trash_document(second.id, user)

      view = open_search(conn, open)
      view |> element("#search-list-trash") |> render_click()

      view |> element("#purge-#{first.id}") |> render_click()
      refute has_element?(view, "#purge-#{first.id}")
      assert has_element?(view, "#purge-#{second.id}")

      view |> element("#search-empty-trash") |> render_click()
      refute has_element?(view, "#purge-#{second.id}")
      refute has_element?(view, "#search-empty-trash")
      assert Document.list_trash(user) == []
    end

    test "a viewer of the document cannot put it in the trash",
         %{user: user, open: open} do
      viewer = register_user()
      Fixtures.share!(user, open, viewer, :viewer)
      {:ok, view, _html} = live(log_in(build_conn(), viewer), ~p"/documents/#{open.id}")

      refute has_element?(view, "#trash-button")
    end

    test "another page showing a document put in the trash leaves it",
         %{conn: conn, user: user, open: open} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{open.id}")

      :ok = Document.trash_document(open.id, user)

      assert_redirect(view, ~p"/documents")
    end
  end
end
