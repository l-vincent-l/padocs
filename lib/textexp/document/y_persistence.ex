defmodule Textexp.Document.YPersistence do
  @moduledoc """
  Yjs persistence of a `Textexp.Document.Document`, modeled on y-sweet: one
  full snapshot per document, rewritten at most every 10 s.

  - on load (`bind/3`): the snapshot is applied;
  - on each edit (`update_v1/4`): nothing is written, the document is only
    marked as modified (`:dirty`);
  - the snapshot is saved (`flush/3`) if the document was modified:
    - every 10 s, called by the DocServer;
    - when the DocServer stops (`unbind/3`), including on application shutdown.

  When the DocServer stops, a document with neither title nor body (typically
  created then left empty) is deleted instead of saved, and
  `{:document_deleted, document_id}` is broadcast on `documents_topic/0`.

  After a crash, the edits of the last 10 seconds are missing from the
  database; Yjs clients send them again when they resync.

  Updates applied on load use the `YPhoenix.Persistence.origin/0` origin,
  which the DocServer ignores.

  Its operations are done without user: the DocServer is shared by all the
  document's clients and saves on its own (timer, shutdown). It checks the
  rights of the clients joining it (see `Textexp.Document.Access`).
  """
  @behaviour YPhoenix.Persistence

  require Logger

  alias Textexp.Document
  alias Textexp.Document.Body

  @origin YPhoenix.Persistence.origin()
  @slow_ms 200

  @doc """
  PubSub topic on which `{:document_updated, document_id, at, title}` is
  broadcast each time the document is saved; saving gives a title to a
  document that has none. Renames and changes of tags are broadcast there
  too (see `Textexp.Document.rename_document/3` and `add_tag/3`).
  """
  def topic(document_id), do: "document:#{document_id}"

  @doc """
  PubSub topic on which `{:document_deleted, document_id}` is broadcast when an
  empty document is deleted.
  """
  def documents_topic, do: "documents"

  @impl true
  def bind(state, document_id, doc) do
    document = timed(:load, document_id, fn -> Document.get_document!(document_id) end)

    if document.snapshot do
      Yex.Doc.transaction(doc, @origin, fn -> Yex.apply_update(doc, document.snapshot) end)
    end

    Map.merge(state, %{dirty: false, untitled?: blank?(document.title)})
  end

  @impl true
  def unbind(state, document_id, doc) do
    document = Document.get_document!(document_id)

    # A sub-document needs its parent: an empty parent is kept.
    if blank?(document.title) and Body.empty?(doc) and not Document.has_children?(document_id) do
      timed(:delete, document_id, fn -> Document.delete_document(document_id) end)

      Phoenix.PubSub.broadcast(
        Textexp.PubSub,
        documents_topic(),
        {:document_deleted, document_id}
      )
    else
      flush(state, document_id, doc)
    end

    :ok
  end

  @impl true
  def update_v1(state, _update, document_id, doc) do
    state = Map.put(state, :dirty, true)

    # The first text of an untitled document is saved at once, which gives it
    # a title (see Document.save_snapshot/3) without waiting for the next
    # flush.
    if state[:untitled?] and Body.excerpt(doc) != nil do
      state |> flush(document_id, doc) |> Map.put(:untitled?, false)
    else
      state
    end
  end

  @impl true
  @doc """
  Saves the document's snapshot, and the excerpt of its body, if it was
  modified since the last save; does nothing otherwise.
  """
  def flush(%{dirty: false} = state, _document_id, _doc), do: state

  def flush(state, document_id, doc) do
    snapshot = Yex.encode_state_as_update!(doc)

    document =
      timed(:save, document_id, fn ->
        Document.save_snapshot(document_id, snapshot, Body.excerpt(doc))
      end)

    Phoenix.PubSub.broadcast(
      Textexp.PubSub,
      topic(document_id),
      {:document_updated, document_id, document.updated_at, document.title}
    )

    Map.put(state, :dirty, false)
  end

  defp blank?(title), do: is_nil(title) or String.trim(title) == ""

  # Measures a database operation done in the DocServer, which blocks all the
  # document's clients meanwhile. Emits `[:textexp, :y_persistence, :stop]` and
  # logs slow operations along with the DocServer's message queue length.
  defp timed(operation, document_id, fun) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start

    :telemetry.execute([:textexp, :y_persistence, :stop], %{duration: duration}, %{
      operation: operation,
      document_id: document_id
    })

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    if duration_ms >= @slow_ms do
      {:message_queue_len, queue} = Process.info(self(), :message_queue_len)

      Logger.warning(
        "Slow #{operation} for document #{document_id}: #{duration_ms} ms " <>
          "(#{queue} messages waiting in the DocServer)"
      )
    end

    result
  end
end
