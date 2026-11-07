defmodule Textexp.Document.SearchIndexTest do
  use Textexp.DataCase

  alias Textexp.Document.SearchIndex
  alias Textexp.Fixtures

  setup do
    user = Fixtures.confirmed_user()
    %{user: user, document: Fixtures.create_document!(user, %{title: "Recette de la tarte"})}
  end

  test "searches the documents of its user", %{user: user, document: document} do
    index = start_supervised!({SearchIndex, user})

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "tarte")
    assert id == document.id
    assert {:ok, []} = SearchIndex.search(index, "gâteau")
  end

  test "finds the other forms of a word, whatever its accents", %{user: user} do
    statuts = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    ecole = Fixtures.create_document!(user, %{title: "Rentrée à l'École"})
    index = start_supervised!({SearchIndex, user})

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "statut")
    assert id == statuts.id
    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "ecoles")
    assert id == ecole.id
  end

  test "takes apostrophes as word separators, not quotes", %{user: user} do
    statuts = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    index = start_supervised!({SearchIndex, user})

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "l'association")
    assert id == statuts.id
  end

  test "finds the words its last word starts", %{user: user} do
    association = Fixtures.create_document!(user, %{title: "Les statuts de l'association"})
    index = start_supervised!({SearchIndex, user})

    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "associa")
    assert id == association.id
    assert {:ok, [%{id: ^id}]} = SearchIndex.search(index, "l'Associ")
    # only the last word
    assert {:ok, []} = SearchIndex.search(index, "assoc tartelette")
    # a single letter would find too many words
    assert {:ok, []} = SearchIndex.search(index, "z")
  end

  test "searches among the documents carrying a tag", %{user: user, document: document} do
    for n <- 1..20, do: Fixtures.create_document!(user, %{title: "Tarte n°#{n}"})
    {:ok, tag} = Textexp.Document.add_tag(document.id, user, "Desserts")
    index = start_supervised!({SearchIndex, user})

    # filtered before the 20 best matches are kept
    assert {:ok, [%{id: id}]} = SearchIndex.search(index, "tarte", tag.id)
    assert id == document.id
    assert {:ok, []} = SearchIndex.search(index, "statuts", tag.id)
  end

  test "stop/1 ends it at once, without ending its caller", %{user: user} do
    {:ok, index} = SearchIndex.start_link(user)
    # Built: stopped in the middle of its query, it would cut the connection
    # of the next test
    {:ok, _} = SearchIndex.search(index, "tarte")
    ref = Process.monitor(index)

    assert :ok = SearchIndex.stop(index)

    assert_receive {:DOWN, ^ref, :process, ^index, :shutdown}
    assert Process.alive?(self())
  end

  test "ends with the process that started it", %{user: user} do
    test = self()

    owner =
      spawn(fn ->
        {:ok, index} = SearchIndex.start_link(user)
        {:ok, _} = SearchIndex.search(index, "tarte")
        send(test, {:index, index})
        receive do: (:stop -> exit(:shutdown))
      end)

    assert_receive {:index, index}
    ref = Process.monitor(index)
    send(owner, :stop)

    assert_receive {:DOWN, ^ref, :process, ^index, :shutdown}
  end
end
