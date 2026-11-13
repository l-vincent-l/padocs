defmodule Padocs.Document.ImportTest do
  use Padocs.DataCase

  alias Padocs.Fixtures

  alias Padocs.Document

  defp register_user, do: Fixtures.register_user()

  # The Yjs state of a BlockNote document holding one paragraph.
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

  setup do
    %{user: register_user()}
  end

  test "creates the document with its content and excerpt", %{user: user} do
    assert {:ok, document} = Document.import_document(user, "Recette", state("Des crêpes"))

    assert document.title == "Recette"
    assert document.owner_id == user.id
    assert document.excerpt == "Des crêpes"
    assert Document.markdown(document) == "Des crêpes"
  end

  test "refuses a state that is not Yjs", %{user: user} do
    assert {:error, changeset} = Document.import_document(user, "Bad", <<1, 2, 3>>)
    assert "contenu illisible" in errors_on(changeset).snapshot
  end

  test "refuses a too large state", %{user: user} do
    assert {:error, changeset} =
             Document.import_document(user, "Big", :binary.copy("x", 5_000_001))

    assert "contenu trop volumineux" in errors_on(changeset).snapshot
  end
end
