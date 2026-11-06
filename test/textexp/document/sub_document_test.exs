defmodule Textexp.Document.SubDocumentTest do
  use Textexp.DataCase

  alias Textexp.Document
  alias Textexp.Document.Access
  alias Textexp.Fixtures

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
end
