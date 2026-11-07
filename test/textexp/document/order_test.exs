defmodule Textexp.Document.OrderTest do
  use Textexp.DataCase

  alias Textexp.Document
  alias Textexp.Fixtures

  setup do
    owner = Fixtures.confirmed_user()
    parent = Fixtures.create_document!(owner, %{title: "Projet"})

    [a, b, c] =
      for _ <- 1..3 do
        {:ok, child} = Document.create_sub_document(parent.id, owner)
        child
      end

    %{owner: owner, parent: parent, a: a, b: b, c: c}
  end

  # The ids of the sub-documents of `parent`, in their order.
  defp order(parent) do
    SqliteRepo.all(
      from d in Document.Document,
        where: d.parent_id == ^parent.id,
        order_by: [asc: d.position],
        select: d.id
    )
  end

  test "a new sub-document goes after the others", %{a: a, b: b, c: c} do
    assert [a.position, b.position, c.position] == [0, 1, 2]
  end

  describe "place_document/4" do
    test "orders a document before or after a sibling",
         %{owner: owner, parent: parent, a: a, b: b, c: c} do
      Phoenix.PubSub.subscribe(Textexp.PubSub, Document.YPersistence.documents_topic())

      assert {:ok, %{position: 0}} = Document.place_document(c.id, a.id, :before, owner)
      assert order(parent) == [c.id, a.id, b.id]

      parent_id = parent.id
      ids = [c.id, a.id, b.id]
      assert_receive {:children_reordered, ^parent_id, ^ids}

      assert {:ok, _} = Document.place_document(c.id, b.id, :after, owner)
      assert order(parent) == [a.id, b.id, c.id]

      assert {:ok, _} = Document.place_document(a.id, b.id, :after, owner)
      assert order(parent) == [b.id, a.id, c.id]
    end

    test "moves a document under the parent of the sibling, at its place",
         %{owner: owner, parent: parent, a: a, b: b, c: c} do
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      {:ok, x} = Document.create_sub_document(other.id, owner)

      assert {:ok, %{parent_id: parent_id, position: 1}} =
               Document.place_document(x.id, b.id, :before, owner)

      assert parent_id == parent.id
      assert order(parent) == [a.id, x.id, b.id, c.id]
    end

    test "an editor orders the sub-documents, without moving them elsewhere",
         %{owner: owner, parent: parent, a: a, c: c} do
      editor = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, editor, :editor)

      assert {:ok, _} = Document.place_document(c.id, a.id, :before, editor)
      assert [c_id | _] = order(parent)
      assert c_id == c.id

      # moving one under another parent takes owning it
      other = Fixtures.create_document!(editor, %{title: "À l'éditeur"})
      {:ok, x} = Document.create_sub_document(other.id, editor)
      assert {:error, :forbidden} = Document.place_document(a.id, x.id, :after, editor)
    end

    test "a viewer or a stranger cannot order them",
         %{owner: owner, parent: parent, a: a, b: b, c: c} do
      viewer = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, viewer, :viewer)
      assert {:error, :forbidden} = Document.place_document(c.id, a.id, :before, viewer)

      stranger = Fixtures.confirmed_user()
      assert {:error, :not_found} = Document.place_document(c.id, a.id, :before, stranger)
      assert order(parent) == [a.id, b.id, c.id]
    end

    test "not under itself, nor among the documents at the root",
         %{owner: owner, parent: parent, a: a} do
      {:ok, aa} = Document.create_sub_document(a.id, owner)
      assert {:error, :cycle} = Document.place_document(a.id, aa.id, :before, owner)

      other = Fixtures.create_document!(owner, %{title: "Autre"})
      assert {:error, :forbidden} = Document.place_document(other.id, parent.id, :after, owner)
      assert {:error, :forbidden} = Document.place_document(a.id, a.id, :after, owner)
    end
  end

  test "move_document/4 puts the document at a position, or at the end",
       %{owner: owner, parent: parent, a: a, b: b, c: c} do
    other = Fixtures.create_document!(owner, %{title: "Autre"})
    {:ok, x} = Document.create_sub_document(other.id, owner)
    {:ok, y} = Document.create_sub_document(other.id, owner)

    assert {:ok, %{position: 0}} = Document.move_document(x.id, parent.id, owner, 0)
    assert {:ok, %{position: 4}} = Document.move_document(y.id, parent.id, owner)
    assert order(parent) == [x.id, a.id, b.id, c.id, y.id]
  end
end
