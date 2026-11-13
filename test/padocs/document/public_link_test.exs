defmodule Padocs.Document.PublicLinkTest do
  use Padocs.DataCase

  alias Padocs.Document
  alias Padocs.Fixtures

  defp register_user, do: Fixtures.confirmed_user()

  setup do
    owner = register_user()
    %{owner: owner, document: Fixtures.create_document!(owner, %{title: "Notes"})}
  end

  test "a document has no public link at first", %{owner: owner, document: document} do
    assert {:ok, nil} = Document.public_link_token(owner, document.id)
    assert Document.public_token(document.id) == nil
  end

  test "the owner gives a link, which reads the document", %{owner: owner, document: document} do
    assert {:ok, token} = Document.enable_public_link(owner, document.id)
    assert byte_size(token) >= 24
    assert {:ok, ^token} = Document.public_link_token(owner, document.id)

    assert {:ok, public} = Document.get_public_document(token)
    assert public.id == document.id
    assert public.title == "Notes"
    assert public.role == :viewer
    # the token is not read along with the document
    assert public.public_token == nil
  end

  test "a new link replaces the previous one", %{owner: owner, document: document} do
    {:ok, old} = Document.enable_public_link(owner, document.id)
    {:ok, new} = Document.enable_public_link(owner, document.id)

    assert old != new
    assert {:error, :not_found} = Document.get_public_document(old)
    assert {:ok, _} = Document.get_public_document(new)
  end

  test "a link removed no longer reads it", %{owner: owner, document: document} do
    {:ok, token} = Document.enable_public_link(owner, document.id)
    assert :ok = Document.disable_public_link(owner, document.id)

    assert {:error, :not_found} = Document.get_public_document(token)
    assert {:ok, nil} = Document.public_link_token(owner, document.id)
  end

  test "the change is broadcast to the document's DocServer", %{owner: owner, document: document} do
    Phoenix.PubSub.subscribe(Padocs.PubSub, Document.members_topic(document.id))
    id = document.id

    {:ok, token} = Document.enable_public_link(owner, id)
    assert_receive {:public_link_changed, ^id, ^token}

    :ok = Document.disable_public_link(owner, id)
    assert_receive {:public_link_changed, ^id, nil}
  end

  test "only who may share it gives or sees a link", %{owner: owner, document: document} do
    editor = register_user()
    viewer = register_user()
    Fixtures.share!(owner, document, editor, :editor)
    Fixtures.share!(owner, document, viewer, :viewer)
    {:ok, _token} = Document.enable_public_link(owner, document.id)

    for user <- [editor, viewer, register_user()] do
      assert {:error, :forbidden} = Document.enable_public_link(user, document.id)
      assert {:error, :forbidden} = Document.disable_public_link(user, document.id)
      assert {:error, :forbidden} = Document.public_link_token(user, document.id)
    end
  end

  test "the owner of a parent gives a sub-document a link", %{owner: owner, document: document} do
    {:ok, child} = Document.create_sub_document(document.id, owner)
    member = register_user()
    Fixtures.share!(owner, document, member, :editor)

    assert {:ok, token} = Document.enable_public_link(owner, child.id)
    assert {:ok, %{id: id}} = Document.get_public_document(token)
    assert id == child.id
    # a link of the parent does not read its sub-documents
    {:ok, parent_token} = Document.enable_public_link(owner, document.id)
    assert {:ok, %{id: parent_id}} = Document.get_public_document(parent_token)
    assert parent_id == document.id
  end

  test "a document in the trash is not read by its link", %{owner: owner, document: document} do
    {:ok, token} = Document.enable_public_link(owner, document.id)
    :ok = Document.trash_document(document.id, owner)

    assert {:error, :not_found} = Document.get_public_document(token)
    assert Document.public_token(document.id) == nil

    {:ok, _} = Document.restore_document(document.id, owner)
    assert {:ok, _} = Document.get_public_document(token)
  end

  test "an empty or unknown token reads nothing" do
    assert {:error, :not_found} = Document.get_public_document("")
    assert {:error, :not_found} = Document.get_public_document("unknown")
    assert {:error, :not_found} = Document.get_public_document(nil)
  end
end
