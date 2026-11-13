defmodule Padocs.Document.SubDocumentTest do
  use Padocs.DataCase

  alias Padocs.Document
  alias Padocs.Document.Access
  alias Padocs.Fixtures

  setup do
    owner = Fixtures.confirmed_user()
    parent = Fixtures.create_document!(owner, %{title: "Projet"})
    {:ok, child} = Document.create_sub_document(parent.id, owner)
    {:ok, grandchild} = Document.create_sub_document(child.id, owner)
    %{owner: owner, parent: parent, child: child, grandchild: grandchild}
  end

  test "a sub-document is created under a document its user can write",
       %{owner: owner, parent: parent, child: child} do
    assert child.parent_id == parent.id
    assert child.owner_id == owner.id

    viewer = Fixtures.confirmed_user()
    Fixtures.share!(owner, parent, viewer, :viewer)
    assert {:error, :forbidden} = Document.create_sub_document(parent.id, viewer)

    stranger = Fixtures.confirmed_user()
    assert {:error, :forbidden} = Document.create_sub_document(parent.id, stranger)
  end

  test "the accesses to a document apply to its descendants",
       %{owner: owner, parent: parent, grandchild: grandchild} do
    editor = Fixtures.confirmed_user()
    Fixtures.share!(owner, parent, editor, :editor)

    assert {:ok, %{role: :editor}} = Document.get_document(grandchild.id, editor)
    assert grandchild.id in Enum.map(Document.list_documents(editor), & &1.id)

    stranger = Fixtures.confirmed_user()
    assert {:error, :not_found} = Document.get_document(grandchild.id, stranger)
  end

  test "the best role counts, on the document or an ancestor",
       %{owner: owner, parent: parent, child: child} do
    member = Fixtures.confirmed_user()
    Fixtures.share!(owner, parent, member, :viewer)
    Fixtures.share!(owner, child, member, :editor)

    assert {:ok, %{role: :viewer}} = Document.get_document(parent.id, member)
    assert {:ok, %{role: :editor}} = Document.get_document(child.id, member)
  end

  test "an access to a sub-document does not give its parent",
       %{owner: owner, parent: parent, child: child, grandchild: grandchild} do
    member = Fixtures.confirmed_user()
    Fixtures.share!(owner, child, member, :viewer)

    assert {:error, :not_found} = Document.get_document(parent.id, member)
    assert {:ok, _} = Document.get_document(grandchild.id, member)
    # the ancestors shown are those the user can read
    assert [] = Document.list_ancestors(child, member)
    assert [%{id: id}] = Document.list_ancestors(grandchild, member)
    assert id == child.id
  end

  test "the ancestors are listed from the root",
       %{owner: owner, parent: parent, child: child, grandchild: grandchild} do
    assert Enum.map(Document.list_ancestors(grandchild, owner), & &1.id) == [parent.id, child.id]
  end

  test "the DocServer's rights include the inherited roles, and follow their changes",
       %{owner: owner, parent: parent, grandchild: grandchild} do
    editor = Fixtures.confirmed_user()
    Fixtures.share!(owner, parent, editor, :editor)

    {:ok, rights} = Access.init(grandchild.id)
    assert Access.permission(rights, owner) == :write
    assert Access.permission(rights, editor) == :write

    [%{id: membership_id}] = Document.list_members(owner, parent.id)
    {:ok, _} = Document.change_member_role(owner, membership_id, "viewer")

    grandchild_id = grandchild.id
    editor_id = editor.id
    assert_receive {:member_changed, ^grandchild_id, ^editor_id, :viewer} = message
    {:ok, rights} = Access.handle_info(message, rights)
    assert Access.permission(rights, editor) == :read

    :ok = Document.remove_member(owner, membership_id)
    assert_receive {:member_changed, ^grandchild_id, ^editor_id, nil} = message
    {:ok, rights} = Access.handle_info(message, rights)
    assert Access.permission(rights, editor) == :none
  end

  describe "move_document/3" do
    test "moves a document under another, with its descendants",
         %{owner: owner, child: child, grandchild: grandchild} do
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      Phoenix.PubSub.subscribe(Padocs.PubSub, Padocs.Document.YPersistence.documents_topic())

      assert {:ok, %{parent_id: parent_id}} = Document.move_document(child.id, other.id, owner)
      assert parent_id == other.id
      assert_receive {:document_moved, _, ^parent_id}

      assert Enum.map(Document.list_ancestors(grandchild, owner), & &1.id) == [other.id, child.id]
    end

    test "moves a document to the root", %{owner: owner, child: child} do
      assert {:ok, %{parent_id: nil}} = Document.move_document(child.id, nil, owner)
      assert {:ok, %{parent_id: nil}} = Document.get_document(child.id, owner)
    end

    test "refuses to move a document under itself or a descendant",
         %{owner: owner, parent: parent, child: child, grandchild: grandchild} do
      assert {:error, :cycle} = Document.move_document(parent.id, parent.id, owner)
      assert {:error, :cycle} = Document.move_document(parent.id, grandchild.id, owner)
      assert {:ok, %{parent_id: nil}} = Document.get_document(parent.id, owner)
      assert {:ok, %{parent_id: parent_id}} = Document.get_document(child.id, owner)
      assert parent_id == parent.id
    end

    test "needs to share the document and write the new parent",
         %{owner: owner, parent: parent, child: child} do
      editor = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, editor, :editor)
      own = Fixtures.create_document!(editor)
      assert {:error, :forbidden} = Document.move_document(child.id, own.id, editor)

      reader = Fixtures.create_document!(editor)
      Fixtures.share!(editor, reader, owner, :viewer)
      assert {:error, :forbidden} = Document.move_document(child.id, reader.id, owner)

      assert {:error, :forbidden} = Document.move_document(child.id, "nope", owner)
    end

    test "to the root, needs to own the document, not only by inheritance",
         %{owner: owner, child: child} do
      member = Fixtures.confirmed_user()
      Fixtures.share!(owner, child, member, :editor)
      {:ok, own} = Document.create_sub_document(child.id, member)

      # `owner` owns `own` by inheritance: at the root, it would no longer be theirs
      assert {:ok, %{role: :owner}} = Document.get_document(own.id, owner)
      assert {:error, :forbidden} = Document.move_document(own.id, nil, owner)
      assert {:ok, _} = Document.move_document(own.id, nil, member)
    end

    test "broadcasts the roles it changes, on the documents moved",
         %{owner: owner, parent: parent, child: child, grandchild: grandchild} do
      editor = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, editor, :editor)
      viewer = Fixtures.confirmed_user()
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      Fixtures.share!(owner, other, viewer, :viewer)

      for document <- [parent, child, grandchild] do
        Phoenix.PubSub.subscribe(Padocs.PubSub, Document.members_topic(document.id))
      end

      {:ok, _} = Document.move_document(child.id, other.id, owner)

      {child_id, grandchild_id, editor_id, viewer_id} =
        {child.id, grandchild.id, editor.id, viewer.id}

      assert_receive {:member_changed, ^child_id, ^editor_id, nil}
      assert_receive {:member_changed, ^grandchild_id, ^editor_id, nil}
      assert_receive {:member_changed, ^child_id, ^viewer_id, :viewer}
      assert_receive {:member_changed, ^grandchild_id, ^viewer_id, :viewer}
      # the owner keeps their role, the parent left is not moved
      refute_received {:member_changed, _, _, :owner}
      refute_received {:member_changed, _, _, _}
    end
  end

  describe "list_inherited_accesses/2" do
    test "lists the best role of each user on the ancestors, from the nearest",
         %{owner: owner, parent: parent, child: child, grandchild: grandchild} do
      editor = Fixtures.confirmed_user("a-editor@example.com")
      viewer = Fixtures.confirmed_user("b-viewer@example.com")
      Fixtures.share!(owner, parent, editor, :viewer)
      Fixtures.share!(owner, child, editor, :editor)
      Fixtures.share!(owner, parent, viewer, :viewer)
      direct = Fixtures.confirmed_user()
      Fixtures.share!(owner, grandchild, direct, :editor)

      {parent_id, child_id, owner_id} = {parent.id, child.id, owner.id}

      assert [
               %{email: "a-editor@example.com", role: :editor, from: %{id: ^child_id}},
               %{email: "b-viewer@example.com", role: :viewer, from: %{id: ^parent_id}},
               %{user_id: ^owner_id, role: :owner, from: %{id: ^child_id}}
             ] = Document.list_inherited_accesses(owner, grandchild.id)

      assert Document.list_inherited_accesses(owner, parent.id) == []
    end

    test "hides the ancestors the user cannot read",
         %{owner: owner, parent: parent, child: child} do
      member = Fixtures.confirmed_user()
      Fixtures.share!(owner, child, member, :editor)
      {:ok, own} = Document.create_sub_document(child.id, member)
      reader = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, reader, :viewer)

      accesses = Map.new(Document.list_inherited_accesses(member, own.id), &{&1.user_id, &1})

      # `member` can read `child`, not `parent`
      assert %{role: :viewer, from: nil} = accesses[reader.id]
      assert %{role: :owner, from: %{id: child_id}} = accesses[owner.id]
      assert child_id == child.id
    end

    test "is empty for a user who cannot share the document",
         %{owner: owner, parent: parent, child: child} do
      viewer = Fixtures.confirmed_user()
      Fixtures.share!(owner, parent, viewer, :viewer)
      assert Document.list_inherited_accesses(viewer, child.id) == []
    end
  end
end
