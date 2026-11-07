defmodule Textexp.Document.TrashTest do
  use Textexp.DataCase

  alias Textexp.Document
  alias Textexp.Document.Access
  alias Textexp.Fixtures

  setup do
    owner = Fixtures.confirmed_user()
    parent = Fixtures.create_document!(owner, %{title: "Projet"})
    {:ok, child} = Document.create_sub_document(parent.id, owner)
    %{owner: owner, parent: parent, child: child}
  end

  defp ids(documents), do: Enum.map(documents, & &1.id)

  describe "trash_document/2" do
    test "puts a document and its sub-documents in the trash, read by nobody",
         %{owner: owner, parent: parent, child: child} do
      member = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, member, :editor)
      Phoenix.PubSub.subscribe(Textexp.PubSub, Document.YPersistence.documents_topic())

      assert :ok = Document.trash_document(parent.id, owner)

      {parent_id, child_id} = {parent.id, child.id}
      assert_receive {:document_deleted, ^parent_id}
      assert_receive {:document_deleted, ^child_id}

      for user <- [owner, member] do
        assert {:error, :not_found} = Document.get_document(parent.id, user)
        assert {:error, :not_found} = Document.get_document(child.id, user)
        assert Document.list_documents(user) == []
      end

      # its DocServer refuses it
      assert :not_found = Access.init(child.id)
    end

    test "needs to share the document", %{owner: owner, parent: parent} do
      editor = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, editor, :editor)

      assert {:error, :forbidden} = Document.trash_document(parent.id, editor)
      assert {:ok, _} = Document.get_document(parent.id, owner)
    end
  end

  describe "list_trash/1" do
    test "lists what the user owns or deleted, without the sub-documents gone along",
         %{owner: owner, parent: parent} do
      other = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, other, :editor)
      # owned by `other`, deleted by `owner` along with its parent
      {:ok, theirs} = Document.create_sub_document(parent.id, other)

      :ok = Document.trash_document(parent.id, owner)

      assert ids(Document.list_trash(owner)) == [parent.id]
      assert Document.list_trash(other) == []
      refute theirs.id in ids(Document.list_trash(other))
    end
  end

  describe "who can restore or delete for good" do
    test "the owner by inheritance who deleted it loses the trash with the right",
         %{owner: owner, parent: parent} do
      alice = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, alice, :editor)
      {:ok, x} = Document.create_sub_document(parent.id, alice)
      {:ok, c} = Document.create_sub_document(x.id, alice)

      # `owner` owns `c` by inheritance, and deletes it
      :ok = Document.trash_document(c.id, owner)
      assert c.id in ids(Document.list_trash(owner))
      assert c.id in ids(Document.list_trash(alice))

      # `x` leaves `parent`: `owner` has no right on `c` any more
      {:ok, _} = Document.move_document(x.id, nil, alice)

      refute c.id in ids(Document.list_trash(owner))
      assert {:error, :not_found} = Document.purge_document(c.id, owner)
      assert {:error, :not_found} = Document.restore_document(c.id, owner)
      :ok = Document.empty_trash(owner)
      assert Textexp.SqliteRepo.get(Document.Document, c.id)

      # its owner still can
      assert {:ok, _} = Document.restore_document(c.id, alice)
    end

    test "an editor or viewer cannot", %{owner: owner, parent: parent} do
      editor = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, editor, :editor)
      :ok = Document.trash_document(parent.id, owner)

      assert Document.list_trash(editor) == []
      assert {:error, :not_found} = Document.purge_document(parent.id, editor)
    end
  end

  describe "restore_document/2" do
    test "brings back the document with the sub-documents deleted along",
         %{owner: owner, parent: parent, child: child} do
      {:ok, grandchild} = Document.create_sub_document(child.id, owner)
      # deleted before, on its own: it stays in the trash
      :ok = Document.trash_document(grandchild.id, owner)
      :ok = Document.trash_document(parent.id, owner)

      assert {:ok, %{deleted_at: nil}} = Document.restore_document(parent.id, owner)

      assert {:ok, _} = Document.get_document(parent.id, owner)
      assert {:ok, _} = Document.get_document(child.id, owner)
      assert {:error, :not_found} = Document.get_document(grandchild.id, owner)
      assert ids(Document.list_trash(owner)) == [grandchild.id]
    end

    test "only from the user's trash", %{owner: owner, parent: parent, child: child} do
      :ok = Document.trash_document(parent.id, owner)
      stranger = Fixtures.confirmed_user()

      assert {:error, :not_found} = Document.restore_document(parent.id, stranger)
      # a sub-document goes back with its parent
      assert {:error, :not_found} = Document.restore_document(child.id, owner)
      assert {:error, :not_found} = Document.restore_document("nope", owner)
    end
  end

  describe "purge_document/2 and empty_trash/1" do
    test "delete for good", %{owner: owner, parent: parent, child: child} do
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      :ok = Document.trash_document(parent.id, owner)
      :ok = Document.trash_document(other.id, owner)

      assert {:error, :not_found} = Document.purge_document(child.id, owner)
      assert :ok = Document.purge_document(parent.id, owner)
      refute Textexp.SqliteRepo.get(Document.Document, parent.id)
      refute Textexp.SqliteRepo.get(Document.Document, child.id)

      assert :ok = Document.empty_trash(owner)
      assert Document.list_trash(owner) == []
      refute Textexp.SqliteRepo.get(Document.Document, other.id)
    end
  end

  describe "the lists of the search" do
    test "recent documents, the last opened first, still readable",
         %{owner: owner, parent: parent, child: child} do
      other = Fixtures.create_document!(owner, %{title: "Autre"})

      for document <- [child, other, parent], do: Document.opened(owner, document)
      assert ids(Document.list_recent_documents(owner)) == [parent.id, other.id, child.id]

      Document.opened(owner, child)
      assert ids(Document.list_recent_documents(owner, 2)) == [child.id, parent.id]

      :ok = Document.trash_document(other.id, owner)
      refute other.id in ids(Document.list_recent_documents(owner))
    end

    test "own and shared documents", %{owner: owner, parent: parent, child: child} do
      member = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, member, :editor)
      {:ok, theirs} = Document.create_sub_document(parent.id, member)
      own = Fixtures.create_document!(member, %{title: "À moi"})

      assert Enum.sort(ids(Document.list_own_documents(member))) ==
               Enum.sort([theirs.id, own.id])

      assert Enum.sort(ids(Document.list_shared_documents(member))) ==
               Enum.sort([parent.id, child.id])

      assert [%{role: :editor} | _] = Document.list_shared_documents(member)
    end
  end
end
