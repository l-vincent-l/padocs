defmodule Padocs.FilesTest do
  use Padocs.DataCase

  alias Padocs.{Document, Files, Fixtures}

  # The first bytes of a PNG are all that is checked.
  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "rest of the image">>

  defp register_user, do: Fixtures.confirmed_user()

  setup do
    owner = register_user()
    %{owner: owner, document: Fixtures.create_document!(owner, %{title: "Notes"})}
  end

  describe "upload" do
    test "the owner or an editor adds an image to a document", %{
      owner: owner,
      document: document
    } do
      editor = register_user()
      Fixtures.share!(owner, document, editor, :editor)

      for user <- [owner, editor] do
        assert {:ok, file} = Files.upload(user, document.id, @png)
        assert file.document_id == document.id
        assert file.content_type == "image/png"
        assert file.size == byte_size(@png)
        assert Files.read(file) == {:ok, @png}
      end
    end

    test "a viewer or a stranger cannot", %{owner: owner, document: document} do
      viewer = register_user()
      Fixtures.share!(owner, document, viewer, :viewer)

      for user <- [viewer, register_user()] do
        assert {:error, :forbidden} = Files.upload(user, document.id, @png)
      end

      assert {:error, :forbidden} = Files.upload(owner, "not-an-id", @png)
    end

    test "only images, recognized by their bytes", %{owner: owner, document: document} do
      for data <- [
            "<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>",
            "just text",
            ""
          ] do
        assert {:error, :unsupported_type} = Files.upload(owner, document.id, data)
      end

      assert {:ok, %{content_type: "image/jpeg"}} =
               Files.upload(owner, document.id, <<0xFF, 0xD8, 0xFF, 0xE0, "jpeg">>)

      assert {:ok, %{content_type: "image/gif"}} =
               Files.upload(owner, document.id, "GIF89a" <> "gif")

      assert {:ok, %{content_type: "image/webp"}} =
               Files.upload(owner, document.id, "RIFF" <> <<0::32>> <> "WEBPVP8 ")
    end

    test "not beyond the largest size", %{owner: owner, document: document} do
      data = @png <> :binary.copy("x", Files.max_bytes())
      assert {:error, :too_large} = Files.upload(owner, document.id, data)
    end
  end

  describe "get_readable" do
    test "whoever can read the document reads its files", %{owner: owner, document: document} do
      viewer = register_user()
      Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, file} = Files.upload(owner, document.id, @png)

      assert {:ok, _} = Files.get_readable(file.id, owner)
      assert {:ok, _} = Files.get_readable(file.id, viewer)
      assert {:error, :not_found} = Files.get_readable(file.id, register_user())
      assert {:error, :not_found} = Files.get_readable(file.id, nil)
      assert {:error, :not_found} = Files.get_readable("nope", owner)
    end

    test "anyone, while the document has a public link", %{owner: owner, document: document} do
      {:ok, file} = Files.upload(owner, document.id, @png)

      {:ok, _token} = Document.enable_public_link(owner, document.id)
      assert {:ok, _} = Files.get_readable(file.id, nil)

      :ok = Document.disable_public_link(owner, document.id)
      assert {:error, :not_found} = Files.get_readable(file.id, nil)
    end

    test "nobody but its owner, a file of a document in the trash", %{
      owner: owner,
      document: document
    } do
      viewer = register_user()
      Fixtures.share!(owner, document, viewer, :viewer)
      {:ok, _token} = Document.enable_public_link(owner, document.id)
      {:ok, file} = Files.upload(owner, document.id, @png)

      :ok = Document.trash_document(document.id, owner)

      assert {:error, :not_found} = Files.get_readable(file.id, viewer)
      assert {:error, :not_found} = Files.get_readable(file.id, nil)
    end
  end

  describe "files of an import" do
    test "are their owner's only, until put into the document", %{owner: owner} do
      {:ok, file} = Files.upload(owner, nil, @png)
      assert file.document_id == nil

      assert {:ok, _} = Files.get_readable(file.id, owner)
      assert {:error, :not_found} = Files.get_readable(file.id, register_user())
    end

    test "the import puts them into the new document", %{owner: owner} do
      {:ok, file} = Files.upload(owner, nil, @png)
      {:ok, other} = Files.upload(register_user(), nil, @png)

      {:ok, document} =
        Document.import_document(owner, "Rapport", Fixtures.yjs_state("Texte"), [
          file.id,
          other.id,
          "not-an-id"
        ])

      assert Files.list_ids([document.id]) == [file.id]
    end
  end

  test "deleting a document for good deletes its files and those of its sub-documents", %{
    owner: owner,
    document: document
  } do
    {:ok, child} = Document.create_sub_document(document.id, owner)
    {:ok, file} = Files.upload(owner, document.id, @png)
    {:ok, child_file} = Files.upload(owner, child.id, @png)

    :ok = Document.trash_document(document.id, owner)
    :ok = Document.purge_document(document.id, owner)

    assert Files.list_ids([document.id, child.id]) == []

    for file <- [file, child_file] do
      assert {:error, :enoent} = Files.read(file)
    end
  end
end
