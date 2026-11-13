defmodule Textexp.Document.SearchIndexTest do
  use Textexp.DataCase

  alias Textexp.Document
  alias Textexp.Document.{History, Search, SearchIndex}
  alias Textexp.Fixtures

  setup do
    user = Fixtures.confirmed_user()
    %{user: user, document: Fixtures.create_document!(user, %{title: "Recette de la tarte"})}
  end

  # The documents changed so far indexed, then the ids of those found.
  defp search(query, user, tag_id \\ nil) do
    :ok = SearchIndex.sync()
    query |> Search.search(user, tag_id) |> Enum.map(& &1.id)
  end

  test "searches the documents of its user", %{user: user, document: document} do
    assert search("tarte", user) == [document.id]
    assert search("gâteau", user) == []
  end

  test "finds the other forms of a word, whatever its accents", %{user: user} do
    statuts = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    ecole = Fixtures.create_document!(user, %{title: "Rentrée à l'École"})

    assert search("statut", user) == [statuts.id]
    assert search("ecoles", user) == [ecole.id]
  end

  test "takes apostrophes as word separators, not quotes", %{user: user} do
    statuts = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})

    assert search("l'association", user) == [statuts.id]
  end

  test "finds the words its last word starts", %{user: user} do
    association = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})

    assert search("associa", user) == [association.id]
    assert search("l'Associ", user) == [association.id]
    # only the last word
    assert search("assoc tartelette", user) == []
    # a single letter would find too many words
    assert search("z", user) == []
  end

  test "searches among the documents carrying a tag", %{user: user, document: document} do
    for n <- 1..20, do: Fixtures.create_document!(user, %{title: "Tarte n°#{n}"})
    {:ok, tag} = Document.add_tag(document.id, user, "Desserts")

    # filtered before the 20 best matches are kept
    assert search("tarte", user, tag.id) == [document.id]
    assert search("statuts", user, tag.id) == []
  end

  test "only finds the documents the user can read, before keeping the best", %{
    user: user,
    document: document
  } do
    other = Fixtures.confirmed_user()
    for n <- 1..20, do: Fixtures.create_document!(other, %{title: "Tarte n°#{n}"})

    assert search("tarte", user) == [document.id]

    Fixtures.share!(user, document, other, :viewer)
    assert search("recette", other) == [document.id]
  end

  test "follows the changes of the documents", %{user: user, document: document} do
    {:ok, _} = Document.rename_document(document, user, "Recette du gâteau")
    assert search("gâteau", user) == [document.id]
    assert search("tarte", user) == []

    History.append(document.id, state("Le chat dort"), "Le chat dort")
    assert search("chat", user) == [document.id]

    :ok = Document.delete_document(document.id)
    assert search("gâteau", user) == []
  end

  test "searches nothing for an empty or invalid query", %{user: user} do
    assert search("  ", user) == []
    assert search("tarte AND (", user) == []
  end

  defp state(text) do
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, "document-store")

    Yex.XmlFragment.push(
      fragment,
      Yex.XmlElementPrelim.new("blockGroup", [
        Yex.XmlElementPrelim.new("blockContainer", [
          Yex.XmlElementPrelim.new("paragraph", [Yex.XmlTextPrelim.from(text)])
        ])
      ])
    )

    Yex.encode_state_as_update!(doc)
  end
end
