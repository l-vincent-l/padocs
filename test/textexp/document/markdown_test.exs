defmodule Textexp.Document.MarkdownTest do
  use Textexp.DataCase

  alias Textexp.Fixtures

  alias Textexp.Document

  defp register_user, do: Fixtures.register_user()

  defp snapshot(text) do
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

  setup do
    %{user: register_user()}
  end

  test "is the body of the saved snapshot", %{user: user} do
    document = Fixtures.create_document!(user, %{title: "Notes"})
    Document.History.append(document.id, snapshot("Hello"), "Hello")

    assert document.id |> Document.get_document!() |> Document.markdown() == "Hello"
  end

  test "is empty without snapshot", %{user: user} do
    document = Fixtures.create_document!(user, %{title: "Notes"})

    assert Document.markdown(document) == ""
  end
end
