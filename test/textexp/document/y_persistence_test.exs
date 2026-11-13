defmodule Textexp.Document.YPersistenceTest do
  use Textexp.DataCase

  alias Textexp.Fixtures

  alias Textexp.Document
  alias Textexp.Document.YPersistence
  alias YPhoenix.DocServer

  defp register_user, do: Fixtures.register_user()

  defp saved(id), do: Textexp.SqliteRepo.get(Document.Document, id)

  defp text_update(content) do
    source = Yex.Doc.new()
    source |> Yex.Doc.get_text("t") |> Yex.Text.insert(0, content)
    Yex.encode_state_as_update!(source)
  end

  # Body as written by the BlockNote editor: one block per `{tag, text}` pair.
  defp body_update(blocks) do
    source = Yex.Doc.new()

    containers =
      for {tag, text} <- blocks do
        children = if text == "", do: [], else: [Yex.XmlTextPrelim.from(text)]
        Yex.XmlElementPrelim.new("blockContainer", [Yex.XmlElementPrelim.new(tag, children)])
      end

    source
    |> Yex.Doc.get_xml_fragment("document-store")
    |> Yex.XmlFragment.push(Yex.XmlElementPrelim.new("blockGroup", containers))

    Yex.encode_state_as_update!(source)
  end

  defp text(doc), do: doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()

  defp loaded_text(document_id) do
    doc = Yex.Doc.new()
    YPersistence.bind(%{}, document_id, doc)
    text(doc)
  end

  # Applies an edit to `doc` and reports it to the persistence, as the
  # DocServer does.
  defp edit(state, document, doc, content) do
    update = text_update(content)
    Yex.apply_update(doc, update)
    YPersistence.update_v1(state, update, document.id, doc)
  end

  # Titled, so that unbind keeps it (see "unbind of an empty document").
  setup do
    %{document: Fixtures.create_document!(register_user(), %{title: "Notes"})}
  end

  test "loading applies the saved snapshot", %{document: document} do
    Document.History.append(document.id, text_update("hello"), nil)

    assert loaded_text(document.id) == "hello"
  end

  test "edits are not written until the document is flushed", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    refute Document.get_document!(document.id).snapshot

    YPersistence.flush(state, document.id, doc)

    assert loaded_text(document.id) == "hello"
  end

  test "flush saves the excerpt of the body", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    update = body_update([{"heading", "Title"}, {"paragraph", ""}, {"paragraph", "Body"}])
    Yex.apply_update(doc, update)
    state = YPersistence.update_v1(state, update, document.id, doc)

    YPersistence.flush(state, document.id, doc)

    assert Document.get_document!(document.id).excerpt == "Title\nBody"
  end

  test "flush does nothing when nothing changed", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)

    assert YPersistence.flush(state, document.id, doc) == state

    assert Document.get_document!(document.id).updated_at ==
             document.updated_at
  end

  test "flush only writes once per batch of edits", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    state = YPersistence.flush(state, document.id, doc)
    saved = Document.get_document!(document.id)

    assert YPersistence.flush(state, document.id, doc) == state
    assert Document.get_document!(document.id).updated_at == saved.updated_at
  end

  test "each flush appends one update to the log", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")
    state = edit(state, document, doc, " world")

    state = YPersistence.flush(state, document.id, doc)
    state = edit(state, document, doc, "!")
    YPersistence.flush(state, document.id, doc)

    assert Document.History.pending_count(document.id) == 2
    # each edit is from another client, inserting at 0 (see text_update/1)
    assert loaded_text(document.id) |> String.length() == String.length("hello world!")
  end

  test "the excerpt is saved at most every 10 s, and on stopping", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    update = body_update([{"paragraph", "First"}])
    Yex.apply_update(doc, update)
    state = YPersistence.update_v1(state, update, document.id, doc)
    state = YPersistence.flush(state, document.id, doc)

    assert Document.get_document!(document.id).excerpt == "First"

    update = body_update([{"paragraph", "Second"}])
    Yex.apply_update(doc, update)
    state = YPersistence.update_v1(state, update, document.id, doc)
    state = YPersistence.flush(state, document.id, doc)

    # appended, the excerpt not saved yet
    assert Document.History.pending_count(document.id) == 2
    refute Document.get_document!(document.id).excerpt =~ "Second"

    YPersistence.unbind(state, document.id, doc)

    assert Document.get_document!(document.id).excerpt =~ "Second"
  end

  test "unbind folds the log into the snapshot", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    YPersistence.unbind(state, document.id, doc)

    assert Document.History.pending_count(document.id) == 0
    assert saved(document.id).snapshot
  end

  test "unbind saves pending edits", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")

    YPersistence.unbind(state, document.id, doc)

    assert loaded_text(document.id) == "hello"
  end

  describe "an untitled document" do
    setup %{document: %{owner_id: owner_id}} do
      document = Fixtures.create_document!(%{id: owner_id})
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))
      %{document: document}
    end

    test "is saved with a dated title as soon as it has text", %{document: document} do
      document_id = document.id
      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document_id, doc)

      update = body_update([{"paragraph", "Hello"}])
      Yex.apply_update(doc, update)
      # no flush needed
      YPersistence.update_v1(state, update, document_id, doc)

      title = "Notes du #{Calendar.strftime(Date.utc_today(), "%d-%m-%Y")}"
      assert Document.get_document!(document_id).title == title
      assert_receive {:document_updated, ^document_id, _at, ^title}
    end

    test "stays untitled without text", %{document: document} do
      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)

      update = body_update([{"paragraph", ""}])
      Yex.apply_update(doc, update)
      state = YPersistence.update_v1(state, update, document.id, doc)
      YPersistence.flush(state, document.id, doc)

      assert Document.get_document!(document.id).title == nil
    end
  end

  test "flush broadcasts the save time and title on the document topic",
       %{document: document} do
    Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.topic(document.id))
    document_id = document.id

    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")
    YPersistence.flush(state, document.id, doc)

    updated_at = Document.get_document!(document.id).updated_at
    assert_receive {:document_updated, ^document_id, ^updated_at, "Notes"}
  end

  test "the last update is the time of the last save", %{document: document} do
    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    state = edit(state, document, doc, "hello")
    YPersistence.flush(state, document.id, doc)

    assert DateTime.compare(saved(document.id).updated_at, document.updated_at) == :gt
  end

  test "emits a telemetry event for each database operation", %{document: document} do
    test_pid = self()
    handler_id = "y-persistence-test-#{inspect(test_pid)}"

    :telemetry.attach(
      handler_id,
      [:textexp, :y_persistence, :stop],
      fn _event, measurements, metadata, _config ->
        send(test_pid, {:y_persistence, metadata.operation, measurements.duration})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    doc = Yex.Doc.new()
    state = YPersistence.bind(%{}, document.id, doc)
    assert_receive {:y_persistence, :load, duration} when is_integer(duration)

    state = edit(state, document, doc, "hello")
    refute_received {:y_persistence, _, _}

    YPersistence.flush(state, document.id, doc)
    assert_receive {:y_persistence, :save, _}
  end

  describe "unbind of an empty document" do
    setup do
      %{document: Fixtures.create_document!(register_user(), %{})}
    end

    defp unbind_with_body(document, blocks) do
      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)
      update = body_update(blocks)
      Yex.apply_update(doc, update)
      state = YPersistence.update_v1(state, update, document.id, doc)
      YPersistence.unbind(state, document.id, doc)
    end

    test "deletes a document without title nor body", %{document: document} do
      Phoenix.PubSub.subscribe(Textexp.PubSub, YPersistence.documents_topic())
      document_id = document.id

      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)
      YPersistence.unbind(state, document.id, doc)

      refute saved(document.id)
      assert_receive {:document_deleted, ^document_id}
    end

    test "deletes a document whose body only has empty paragraphs", %{document: document} do
      unbind_with_body(document, [{"paragraph", ""}, {"paragraph", "  "}])

      refute saved(document.id)
    end

    test "keeps an empty document that has sub-documents", %{document: document} do
      owner = Textexp.SqliteRepo.preload(document, :owner).owner
      {:ok, _child} = Document.create_sub_document(document.id, owner)

      doc = Yex.Doc.new()
      state = YPersistence.bind(%{}, document.id, doc)
      YPersistence.unbind(state, document.id, doc)

      assert saved(document.id)
    end

    test "keeps an untitled document with text", %{document: document} do
      unbind_with_body(document, [{"paragraph", ""}, {"paragraph", "hello"}])

      assert %{snapshot: snapshot} = saved(document.id)
      assert snapshot
    end

    test "keeps an untitled document with a block other than a paragraph",
         %{document: document} do
      unbind_with_body(document, [{"image", ""}])

      assert saved(document.id)
    end

    test "keeps a titled document without body", %{document: document} do
      document = document |> Ecto.Changeset.change(title: "Notes") |> Textexp.SqliteRepo.update!()

      unbind_with_body(document, [])

      assert saved(document.id)
    end
  end

  describe "DocServer" do
    defp start_doc_server(document) do
      start_supervised!(%{
        id: DocServer,
        start:
          {DocServer, :start_link,
           [
             [topic: "y_doc_room:#{document.id}", doc_name: document.id] ++
               TextexpWeb.YDocRoomChannel.doc_server_opts(),
             []
           ]}
      })
    end

    # Sends an edit to the DocServer as a client would.
    defp send_edit(pid, content) do
      {:ok, sync} = Yex.Sync.get_update(text_update(content))
      {:ok, message} = Yex.Sync.message_encode({:sync, sync})
      DocServer.process_message_v1(pid, message, self())
      # applies the message, then handles the resulting update notification
      _ = :sys.get_state(pid)
      _ = :sys.get_state(pid)
    end

    test "starting does not write anything", %{document: document} do
      Document.History.append(document.id, text_update("hello"), nil)
      saved = Document.get_document!(document.id)

      pid = start_doc_server(document)
      # the load-time update message is handled before this call returns
      _ = :sys.get_state(pid)
      send(pid, :flush)
      _ = :sys.get_state(pid)

      assert Document.get_document!(document.id).updated_at == saved.updated_at
    end

    test "edits are saved by the periodic flush", %{document: document} do
      pid = start_doc_server(document)
      send_edit(pid, "hello")

      refute Document.get_document!(document.id).snapshot

      # message normally sent by the DocServer's timer
      send(pid, :flush)
      _ = :sys.get_state(pid)

      assert loaded_text(document.id) == "hello"
    end

    test "edits are saved when the DocServer is shut down", %{document: document} do
      pid = start_doc_server(document)
      send_edit(pid, "hello")

      stop_supervised!(DocServer)

      assert loaded_text(document.id) == "hello"
    end
  end
end
