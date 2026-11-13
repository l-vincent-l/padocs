defmodule Padocs.Document.TagTest do
  use Padocs.DataCase

  alias Padocs.Document
  alias Padocs.Document.Tag
  alias Padocs.Fixtures
  alias Padocs.SqliteRepo, as: Repo

  setup do
    owner = Fixtures.confirmed_user()
    %{owner: owner, document: Fixtures.create_document!(owner, %{title: "Notes"})}
  end

  describe "add_tag/3" do
    test "puts a new tag on the document", %{owner: owner, document: document} do
      assert {:ok, %Tag{label: "Urgent"}} = Document.add_tag(document.id, owner, "  Urgent ")

      assert [%Tag{label: "Urgent", key: "urgent"}] = Document.list_tags(document.id)
    end

    test "reuses the tag of the same label, whatever its case", %{
      owner: owner,
      document: document
    } do
      other = Fixtures.create_document!(owner, %{title: "Other"})
      {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")

      assert {:ok, ^tag} = Document.add_tag(other.id, owner, "urgent")
      assert {:ok, ^tag} = Document.add_tag(other.id, owner, "URGENT")
      assert [^tag] = Document.list_tags(other.id)
      assert Repo.aggregate(Tag, :count) == 1
    end

    test "refuses a blank label", %{owner: owner, document: document} do
      assert {:error, :invalid} = Document.add_tag(document.id, owner, "   ")
    end

    test "is for the users who can write the document", %{owner: owner, document: document} do
      editor = Fixtures.confirmed_user()
      viewer = Fixtures.confirmed_user()
      Fixtures.share!(owner, document, editor, :editor)
      Fixtures.share!(owner, document, viewer, :viewer)

      assert {:ok, _} = Document.add_tag(document.id, editor, "Edited")
      assert {:error, :forbidden} = Document.add_tag(document.id, viewer, "Viewed")
      assert {:error, :forbidden} = Document.add_tag(document.id, Fixtures.confirmed_user(), "X")
      assert [%Tag{label: "Edited"}] = Document.list_tags(document.id)
    end

    test "is broadcast", %{owner: owner, document: document} do
      Phoenix.PubSub.subscribe(Padocs.PubSub, Document.YPersistence.topic(document.id))
      {:ok, _} = Document.add_tag(document.id, owner, "Urgent")

      assert_receive {:document_tags_changed, document_id}
      assert document_id == document.id
    end
  end

  describe "remove_tag/3" do
    test "takes the tag off, deleting it with its last document",
         %{owner: owner, document: document} do
      other = Fixtures.create_document!(owner, %{title: "Other"})
      {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")
      {:ok, _} = Document.add_tag(other.id, owner, "Urgent")

      assert :ok = Document.remove_tag(document.id, owner, tag.id)
      assert Document.list_tags(document.id) == []
      assert Repo.get(Tag, tag.id)

      assert :ok = Document.remove_tag(other.id, owner, tag.id)
      refute Repo.get(Tag, tag.id)
    end

    test "is refused to a viewer", %{owner: owner, document: document} do
      viewer = Fixtures.confirmed_user()
      Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")

      assert {:error, :forbidden} = Document.remove_tag(document.id, viewer, tag.id)
      assert [_tag] = Document.list_tags(document.id)
    end
  end

  test "deleting a document deletes the tags only it had", %{owner: owner, document: document} do
    {:ok, tag} = Document.add_tag(document.id, owner, "Urgent")

    Document.delete_document(document.id)

    refute Repo.get(Tag, tag.id)
  end

  test "visible_tags/1 has the tags of the documents the user can read",
       %{owner: owner, document: document} do
    user = Fixtures.confirmed_user()
    shared = Fixtures.create_document!(owner, %{title: "Shared"})
    Fixtures.share!(owner, shared, user, :viewer)
    own = Fixtures.create_document!(user, %{title: "Mine"})
    {:ok, _} = Document.add_tag(document.id, owner, "Secret")
    {:ok, _} = Document.add_tag(shared.id, owner, "Shared")
    {:ok, _} = Document.add_tag(own.id, user, "Mine")
    {:ok, _} = Document.add_tag(own.id, user, "Shared")

    assert user |> Document.visible_tags() |> Enum.map(& &1.label) == ["Mine", "Shared"]
  end

  test "search_tags/2 has the visible tags whose label contains the query",
       %{owner: owner, document: document} do
    user = Fixtures.confirmed_user()
    shared = Fixtures.create_document!(owner, %{title: "Shared"})
    Fixtures.share!(owner, shared, user, :viewer)
    {:ok, _} = Document.add_tag(shared.id, owner, "Recettes")
    {:ok, _} = Document.add_tag(shared.id, owner, "Récréation")
    {:ok, _} = Document.add_tag(shared.id, owner, "100%")
    {:ok, _} = Document.add_tag(document.id, owner, "Recettes secrètes")

    assert user |> Document.search_tags(" REC ") |> Enum.map(& &1.label) == ["Recettes"]
    assert user |> Document.search_tags("réc") |> Enum.map(& &1.label) == ["Récréation"]
    # Not a LIKE pattern
    assert user |> Document.search_tags("%") |> Enum.map(& &1.label) == ["100%"]
  end

  test "list_documents_tagged/2 has the readable documents carrying the tag",
       %{owner: owner, document: document} do
    user = Fixtures.confirmed_user()
    shared = Fixtures.create_document!(owner, %{title: "Shared"})
    Fixtures.share!(owner, shared, user, :viewer)
    untagged = Fixtures.create_document!(user, %{title: "Untagged"})
    {:ok, tag} = Document.add_tag(shared.id, owner, "Recettes")
    {:ok, _} = Document.add_tag(document.id, owner, "Recettes")

    assert [%{id: id}] = Document.list_documents_tagged(user, tag.id)
    assert id == shared.id
    refute id == untagged.id
  end

  describe "top_tags/2" do
    test "has the most searched tags first, then the most used, then by label",
         %{owner: owner, document: document} do
      other = Fixtures.create_document!(owner, %{title: "Other"})

      for label <- ["Bleu", "Arbre", "Ciel", "Dune"],
          do: Document.add_tag(document.id, owner, label)

      {:ok, _} = Document.add_tag(other.id, owner, "Dune")
      {:ok, ciel} = Document.add_tag(other.id, owner, "Ciel")
      [bleu] = for t <- Document.list_tags(document.id), t.label == "Bleu", do: t

      Document.record_tag_search(owner, bleu.id)
      Document.record_tag_search(owner, bleu.id)
      Document.record_tag_search(owner, ciel.id)

      assert owner |> Document.top_tags(10) |> Enum.map(& &1.label) ==
               ["Bleu", "Ciel", "Dune", "Arbre"]

      assert owner |> Document.top_tags(2) |> Enum.map(& &1.label) == ["Bleu", "Ciel"]
    end

    test "only counts the user's own searches", %{owner: owner, document: document} do
      user = Fixtures.confirmed_user()
      Fixtures.share!(owner, document, user, :viewer)
      {:ok, _} = Document.add_tag(document.id, owner, "Arbre")
      {:ok, bleu} = Document.add_tag(document.id, owner, "Bleu")
      Document.record_tag_search(owner, bleu.id)

      assert user |> Document.top_tags(10) |> Enum.map(& &1.label) == ["Arbre", "Bleu"]
    end
  end
end
