defmodule Padocs.Document.MembershipTest do
  use Padocs.DataCase

  alias Padocs.Document
  alias Padocs.Fixtures

  defp register_user, do: Fixtures.confirmed_user()

  defp share(owner, document, email, role),
    do: Document.share_document(owner, document.id, %{email: email, role: role})

  setup do
    owner = register_user()
    %{owner: owner, document: Fixtures.create_document!(owner, %{title: "Notes"})}
  end

  describe "share_document" do
    test "gives an editor the right to read and write", %{owner: owner, document: document} do
      editor = register_user()

      assert {:ok, %{role: :editor}} = share(owner, document, editor.email, :editor)

      assert {:ok, %{role: :editor} = document} = Document.get_document(document.id, editor)
      assert {:ok, _} = Document.rename_document(document, editor, "Renamed")
    end

    test "gives a viewer the right to read only", %{owner: owner, document: document} do
      viewer = register_user()
      Fixtures.share!(owner, document, viewer, :viewer)

      assert {:ok, %{role: :viewer} = document} = Document.get_document(document.id, viewer)
      assert {:error, :forbidden} = Document.rename_document(document, viewer, "Renamed")
    end

    test "changes the role of a member", %{owner: owner, document: document} do
      member = register_user()
      Fixtures.share!(owner, document, member, :viewer)
      Fixtures.share!(owner, document, member, :editor)

      assert [%{role: :editor}] = Document.list_members(owner, document.id)
    end

    test "finds the user whatever the case of the address", %{owner: owner, document: document} do
      member = register_user()

      assert {:ok, _} = share(owner, document, String.upcase(member.email), :viewer)
    end

    test "refuses an address without account", %{owner: owner, document: document} do
      assert {:error, changeset} = share(owner, document, "nobody@example.com", :viewer)
      assert "no account has this address" in errors_on(changeset).email
    end

    test "refuses an unconfirmed account", %{owner: owner, document: document} do
      assert {:error, changeset} = share(owner, document, Fixtures.register_user().email, :viewer)
      assert "this account has not confirmed its address yet" in errors_on(changeset).email
    end

    test "refuses the owner's own address", %{owner: owner, document: document} do
      assert {:error, changeset} = share(owner, document, owner.email, :editor)
      assert [message] = errors_on(changeset).email
      assert message =~ "owner"
    end

    test "is reserved to the owner", %{owner: owner, document: document} do
      editor = register_user()
      Fixtures.share!(owner, document, editor, :editor)

      assert {:error, :forbidden} = share(editor, document, register_user().email, :editor)
    end

    test "leaves the document's last update unchanged", %{owner: owner, document: document} do
      {:ok, before} = Document.get_document(document.id, owner)
      Fixtures.share!(owner, document, register_user(), :viewer)
      {:ok, after_share} = Document.get_document(document.id, owner)

      assert after_share.updated_at == before.updated_at
    end
  end

  describe "list_members" do
    test "lists the members to the owner, not to others", %{owner: owner, document: document} do
      member = register_user()
      Fixtures.share!(owner, document, member, :viewer)

      assert [%{user_id: user_id}] = Document.list_members(owner, document.id)
      assert user_id == member.id
      assert Document.list_members(register_user(), document.id) == []
    end
  end

  describe "change_member_role" do
    test "changes what the member may do", %{owner: owner, document: document} do
      member = register_user()
      membership = Fixtures.share!(owner, document, member, :viewer)
      Phoenix.PubSub.subscribe(Padocs.PubSub, Document.members_topic(document.id))

      assert {:ok, %{role: :editor}} = Document.change_member_role(owner, membership.id, "editor")
      assert {:ok, %{role: :editor}} = Document.get_document(document.id, member)
      member_id = member.id
      assert_receive {:member_changed, _, ^member_id, :editor}

      assert {:ok, %{role: :viewer}} = Document.change_member_role(owner, membership.id, "viewer")
      assert {:ok, %{role: :viewer}} = Document.get_document(document.id, member)
    end

    test "is reserved to the owner", %{owner: owner, document: document} do
      member = register_user()
      membership = Fixtures.share!(owner, document, member, :viewer)

      assert {:error, :not_found} = Document.change_member_role(member, membership.id, "editor")
      assert {:ok, %{role: :viewer}} = Document.get_document(document.id, member)
    end

    test "only to editor or viewer", %{owner: owner, document: document} do
      member = register_user()
      membership = Fixtures.share!(owner, document, member, :viewer)

      for role <- ["owner", "", "nope"] do
        assert {:error, :not_found} = Document.change_member_role(owner, membership.id, role)
      end

      assert {:ok, %{role: :viewer}} = Document.get_document(document.id, member)
    end
  end

  describe "remove_member" do
    test "takes the access back", %{owner: owner, document: document} do
      member = register_user()
      membership = Fixtures.share!(owner, document, member, :viewer)

      assert :ok = Document.remove_member(owner, membership.id)
      assert {:error, _} = Document.get_document(document.id, member)
    end

    test "is reserved to the owner", %{owner: owner, document: document} do
      member = register_user()
      membership = Fixtures.share!(owner, document, member, :editor)

      assert {:error, :not_found} = Document.remove_member(member, membership.id)
      assert {:ok, _} = Document.get_document(document.id, member)
    end
  end
end
