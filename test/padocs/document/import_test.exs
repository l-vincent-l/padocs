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
    %{user: Fixtures.confirmed_user()}
  end

  test "creates the document with its content and excerpt", %{user: user} do
    assert {:ok, document} = Document.import_document(user, "Recette", state("Des crêpes"))

    assert document.title == "Recette"
    assert document.owner_id == user.id
    assert document.excerpt == "Des crêpes"
    assert Document.markdown(document) == "Des crêpes"
  end

  test "under a parent the user can write, after its other sub-documents", %{user: user} do
    {:ok, parent} = Document.import_document(user, "Dossier", state(""))
    {:ok, first} = Document.import_document(user, "Un", state("1"), [], parent_id: parent.id)
    {:ok, second} = Document.import_document(user, "Deux", state("2"), [], parent_id: parent.id)

    assert first.parent_id == parent.id
    assert second.position > first.position

    children =
      SqliteRepo.all(
        from d in Padocs.Document.Document,
          where: d.parent_id == ^parent.id,
          order_by: d.position,
          select: d.id
      )

    assert children == [first.id, second.id]
  end

  test "not under a parent the user cannot write", %{user: user} do
    other = register_user()
    {:ok, theirs} = Document.import_document(other, "Le leur", state(""))

    assert {:error, :forbidden} =
             Document.import_document(user, "Intrus", state("x"), [], parent_id: theirs.id)

    viewer_of = Fixtures.create_document!(other, %{title: "Lu"})
    Fixtures.share!(other, viewer_of, user, :viewer)

    assert {:error, :forbidden} =
             Document.import_document(user, "Intrus", state("x"), [], parent_id: viewer_of.id)

    editor_of = Fixtures.create_document!(other, %{title: "Écrit"})
    Fixtures.share!(other, editor_of, user, :editor)

    assert {:ok, document} =
             Document.import_document(user, "Invité", state("x"), [], parent_id: editor_of.id)

    assert document.owner_id == user.id
  end

  test "with its tags, those not valid left out", %{user: user} do
    {:ok, document} =
      Document.import_document(user, "Recette", state("x"), [], tags: ["Dessert", "  ", "Rapide"])

    labels = document.id |> Document.list_tags() |> Enum.map(& &1.label) |> Enum.sort()
    assert labels == ["Dessert", "Rapide"]
  end

  test "refuses a state that is not Yjs", %{user: user} do
    assert {:error, changeset} = Document.import_document(user, "Bad", <<1, 2, 3>>)
    assert "unreadable content" in errors_on(changeset).snapshot
  end

  test "refuses a too large state", %{user: user} do
    assert {:error, changeset} =
             Document.import_document(user, "Big", :binary.copy("x", 5_000_001))

    assert "content too large" in errors_on(changeset).snapshot
  end
end
