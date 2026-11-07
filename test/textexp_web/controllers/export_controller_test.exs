defmodule TextexpWeb.ExportControllerTest do
  use TextexpWeb.ConnCase

  alias Textexp.{Document, Fixtures}

  setup %{conn: conn} do
    owner = Fixtures.confirmed_user()
    document = Fixtures.create_document!(owner, %{title: ~S|Rapport: "2026"/final|})
    Document.save_snapshot(document.id, state("Le chat dort"), "Le chat dort")
    %{conn: Fixtures.log_in(conn, owner), owner: owner, document: document}
  end

  # The Yjs state of a body holding `text` in a paragraph.
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

  test "a PDF, named after the title", %{conn: conn, document: document} do
    conn = get(conn, ~p"/documents/#{document.id}/export/pdf")

    assert "%PDF" <> _ = response(conn, 200)
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/pdf"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert URI.decode(disposition) =~ ~s|filename="Rapport 2026 final.pdf"|
  end

  test "Markdown and the Typst source", %{conn: conn, document: document} do
    assert get(conn, ~p"/documents/#{document.id}/export/md") |> response(200) == "Le chat dort"

    typst = get(conn, ~p"/documents/#{document.id}/export/typ") |> response(200)
    assert typst =~ ~S|#"Le chat dort"|
  end

  test "text looking like EEx or Typst code stays text", %{conn: conn, document: document} do
    text = ~S|<%= raise "boom" %> #read("/etc/passwd")|
    Document.save_snapshot(document.id, state(text), text)

    conn = get(conn, ~p"/documents/#{document.id}/export/pdf")
    assert "%PDF" <> _ = response(conn, 200)
  end

  test "only for a user who can read the document", %{document: document, owner: owner} do
    stranger = Fixtures.confirmed_user()

    conn =
      build_conn() |> Fixtures.log_in(stranger) |> get(~p"/documents/#{document.id}/export/pdf")

    assert response(conn, 404)

    viewer = Fixtures.confirmed_user()
    Fixtures.share!(owner, document, viewer, :viewer)
    conn = build_conn() |> Fixtures.log_in(viewer) |> get(~p"/documents/#{document.id}/export/md")
    assert response(conn, 200) == "Le chat dort"

    :ok = Document.trash_document(document.id, owner)
    conn = build_conn() |> Fixtures.log_in(owner) |> get(~p"/documents/#{document.id}/export/md")
    assert response(conn, 404)
  end

  test "signed out, to the sign-in page", %{document: document} do
    conn = get(build_conn(), ~p"/documents/#{document.id}/export/pdf")
    assert redirected_to(conn) == ~p"/sign-in"
  end

  test "an unknown format or document", %{conn: conn, document: document} do
    assert conn |> get(~p"/documents/#{document.id}/export/exe") |> response(404)
    assert conn |> get(~p"/documents/nope/export/pdf") |> response(404)
  end
end
