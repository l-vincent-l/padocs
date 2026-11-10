defmodule TextexpWeb.DocumentHistoryTest do
  use TextexpWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Textexp.Document.History
  alias Textexp.Fixtures

  defp update(text) do
    doc = Yex.Doc.new()
    doc |> Yex.Doc.get_text("t") |> Yex.Text.insert(0, text)
    Yex.encode_state_as_update!(doc)
  end

  defp open_history(view) do
    view |> element("#history-button") |> render_click()
    view
  end

  setup %{conn: conn} do
    owner = Fixtures.confirmed_user()
    document = Fixtures.create_document!(owner, %{title: "Notes"})
    %{conn: conn, owner: owner, document: document}
  end

  describe "the owner" do
    setup %{conn: conn, owner: owner} do
      %{conn: Fixtures.log_in(conn, owner)}
    end

    test "sees no version of a document never written", %{conn: conn, document: document} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      open_history(view)

      assert has_element?(view, "#history-panel")
      refute has_element?(view, "#history-versions button")
    end

    test "shows a version in place of the editor, then goes back",
         %{conn: conn, document: document} do
      History.append(document.id, update("hello"), "hello")
      [version] = History.versions(document.id)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      open_history(view)
      view |> element("#show-version-#{version.id}") |> render_click()

      assert_push_event(view, "show_version", %{state: state})
      assert Base.decode64!(state) == History.state_at(document.id, version.id)
      assert has_element?(view, "#version-banner")
      assert has_element?(view, "#restore-version")

      view |> element("#leave-version") |> render_click()

      assert_push_event(view, "hide_version", %{})
      refute has_element?(view, "#version-banner")
    end

    test "restores a version through the editor", %{conn: conn, document: document} do
      History.append(document.id, update("hello"), "hello")
      [version] = History.versions(document.id)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      open_history(view)
      view |> element("#show-version-#{version.id}") |> render_click()
      view |> element("#restore-version") |> render_click()

      assert_push_event(view, "restore_version", %{})

      render_hook(view, "version_restored", %{})

      refute has_element?(view, "#version-banner")
      refute has_element?(view, "#history-panel")
    end

    test "is told of a version merged since", %{conn: conn, document: document} do
      History.append(document.id, update("hello"), "hello")
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      open_history(view)

      render_click(view, "show_version", %{"id" => 123_456})

      refute has_element?(view, "#version-banner")
    end

    test "closes the history with Escape", %{conn: conn, document: document} do
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")
      open_history(view)

      view |> element("#history-panel") |> render_keydown(%{"key" => "Escape"})

      refute has_element?(view, "#history-panel")
    end
  end

  describe "a viewer" do
    setup %{conn: conn, owner: owner, document: document} do
      viewer = Fixtures.confirmed_user()
      Fixtures.share!(owner, document, viewer, :viewer)
      %{conn: Fixtures.log_in(conn, viewer)}
    end

    test "reads the versions but cannot restore them", %{conn: conn, document: document} do
      History.append(document.id, update("hello"), "hello")
      [version] = History.versions(document.id)
      {:ok, view, _html} = live(conn, ~p"/documents/#{document.id}")

      open_history(view)
      view |> element("#show-version-#{version.id}") |> render_click()

      assert has_element?(view, "#version-banner")
      refute has_element?(view, "#restore-version")

      render_click(view, "restore_version", %{})

      refute_push_event(view, "restore_version", %{})
    end
  end
end
