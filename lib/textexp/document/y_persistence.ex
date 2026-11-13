defmodule Textexp.Document.YPersistence do
  @moduledoc """
  Yjs persistence of a `Textexp.Document.Document`: a log of its updates (see
  `Textexp.Document.History`), appended about every second while it is being
  edited, and folded from time to time into its snapshot.

  - on load (`bind/3`): its content, the snapshot plus the updates after it,
    is applied;
  - on each edit (`update_v1/4`): nothing is written, the update is kept;
  - the updates kept are merged into one and handed over to
    `Textexp.Document.UpdateWriter` (`flush/3`), which appends those of all
    the documents in one `INSERT`, without the DocServer waiting for it:
    - every second (the DocServer's `flush_interval_ms`, see
      `TextexpWeb.YDocRoomChannel`);
    - when the DocServer stops (`unbind/3`), including on application
      shutdown;
  - the excerpt of the body, and the time of the last edit, are saved at
    most every 10 s: one write per second for each document being edited,
    rather than two;
  - the updates appended are folded into the snapshot, and the history
    thinned out (`History.compact/2`), every 60 of them and when the
    DocServer stops.

  When the DocServer stops, a document with neither title nor body (typically
  created then left empty) is deleted instead of saved, and
  `{:document_deleted, document_id}` is broadcast on `documents_topic/0`.

  After a crash, the edits of the last second or two are missing from the
  database; Yjs clients send them again when they resync. A failed write
  (e.g. the database busy) is logged and tried again later.

  Updates applied on load use the `YPhoenix.Persistence.origin/0` origin,
  which the DocServer ignores.

  Its operations are done without user: the DocServer is shared by all the
  document's clients and saves on its own (timer, shutdown). It checks the
  rights of the clients joining it (see `Textexp.Document.Access`).
  """
  @behaviour YPhoenix.Persistence

  require Logger

  alias Textexp.Document
  alias Textexp.Document.{Body, History, UpdateWriter}

  @origin YPhoenix.Persistence.origin()
  @slow_ms 200
  # Updates appended between two compactions
  @compact_every 60
  # Least time between two saves of the excerpt
  @excerpt_every_ms 10_000

  @doc """
  PubSub topic on which `{:document_updated, document_id, at, title}` is
  broadcast each time the document is saved; saving gives a title to a
  document that has none. Renames and changes of tags are broadcast there
  too (see `Textexp.Document.rename_document/3` and `add_tag/3`).
  """
  def topic(document_id), do: "document:#{document_id}"

  @doc """
  PubSub topic on which `{:document_deleted, document_id}` is broadcast when an
  empty document is deleted, `{:document_moved, document_id, parent_id}`
  when a document is moved (see `Textexp.Document.move_document/4`), and
  `{:children_reordered, parent_id, ids}` when the order of sub-documents
  changes (see `Textexp.Document.place_document/4`).
  """
  def documents_topic, do: "documents"

  @impl true
  def bind(state, document_id, doc) do
    document = timed(:load, document_id, fn -> Document.get_document!(document_id) end)

    if document.snapshot do
      Yex.Doc.transaction(doc, @origin, fn -> Yex.apply_update(doc, document.snapshot) end)
    end

    Map.merge(state, %{
      # the updates not yet appended, the last first
      pending: [],
      started_at: nil,
      ended_at: nil,
      # the updates appended since the last compaction
      appended: History.pending_count(document_id),
      # the end of the edits appended whose excerpt is not saved yet, and
      # when it was last saved (monotonic, ms)
      excerpt_due: nil,
      excerpt_saved_at: nil,
      untitled?: blank?(document.title)
    })
  end

  @impl true
  def unbind(state, document_id, doc) do
    document = Document.fetch_document(document_id)

    cond do
      # deleted for good meanwhile, e.g. from the trash
      is_nil(document) ->
        :ok

      # A sub-document needs its parent: an empty parent is kept.
      blank?(document.title) and Body.empty?(doc) and not Document.has_children?(document_id) ->
        timed(:delete, document_id, fn -> Document.delete_document(document_id) end)

        Phoenix.PubSub.broadcast(
          Textexp.PubSub,
          documents_topic(),
          {:document_deleted, document_id}
        )

      true ->
        state = flush(state, document_id, doc, true)

        # Its updates written before folding them; if that fails, they are
        # written later, and folded the next time.
        if state.appended > 0 and timed(:sync, document_id, &UpdateWriter.sync/0) == :ok do
          compact(document_id)
        end
    end

    :ok
  end

  @impl true
  def update_v1(state, update, document_id, doc) do
    now = DateTime.utc_now()

    state = %{
      state
      | pending: [update | state.pending],
        started_at: state.started_at || now,
        ended_at: now
    }

    # The first text of an untitled document is saved at once, which gives it
    # a title (see History.save_excerpt/3) without waiting for the next flush.
    if state.untitled? and Body.excerpt(doc) != nil do
      state |> flush(document_id, doc, true) |> Map.put(:untitled?, false)
    else
      state
    end
  end

  @impl true
  @doc """
  Hands over the updates received since the last flush, merged into one, to
  `UpdateWriter`; does nothing if there are none. Saves the excerpt of the body, and the time of
  the last edit, at most every #{div(@excerpt_every_ms, 1000)} s. Every
  #{@compact_every} updates appended, they are folded into the snapshot.
  """
  def flush(state, document_id, doc), do: flush(state, document_id, doc, false)

  # `force?`: the excerpt saved now, if anything was appended since.
  defp flush(%{pending: [], excerpt_due: nil} = state, _document_id, _doc, _force?), do: state

  defp flush(state, document_id, doc, force?) do
    state
    |> append(document_id)
    |> save_excerpt(document_id, doc, force?)
    |> maybe_compact(document_id)
  end

  defp append(%{pending: []} = state, _document_id), do: state

  defp append(state, document_id) do
    {:ok, update} = state.pending |> Enum.reverse() |> Yex.merge_updates()
    UpdateWriter.append(document_id, update, state.started_at, state.ended_at)

    %{
      state
      | pending: [],
        started_at: nil,
        ended_at: nil,
        appended: state.appended + 1,
        excerpt_due: state.ended_at
    }
  end

  defp save_excerpt(%{excerpt_due: nil} = state, _document_id, _doc, _force?), do: state

  defp save_excerpt(state, document_id, doc, force?) do
    now = System.monotonic_time(:millisecond)

    if force? or state.excerpt_saved_at == nil or
         now - state.excerpt_saved_at >= @excerpt_every_ms do
      result =
        attempt(:excerpt, document_id, fn ->
          History.save_excerpt(document_id, Body.excerpt(doc), state.excerpt_due)
        end)

      case result do
        {:ok, document} ->
          # nil: deleted for good, nothing to tell
          if document do
            Phoenix.PubSub.broadcast(
              Textexp.PubSub,
              topic(document_id),
              {:document_updated, document_id, document.updated_at, document.title}
            )
          end

          %{state | excerpt_due: nil, excerpt_saved_at: now}

        :error ->
          state
      end
    else
      state
    end
  end

  defp maybe_compact(state, document_id) do
    if state.appended >= @compact_every and compact(document_id) == :ok,
      do: %{state | appended: 0},
      else: state
  end

  # :ok, or :error if it failed, to try again at the next flush
  defp compact(document_id) do
    case attempt(:compact, document_id, fn -> History.compact(document_id) end) do
      {:ok, _} -> :ok
      :error -> :error
    end
  end

  # `{:ok, result}`, or `:error` when the database failed (e.g. busy): logged,
  # so that the DocServer, and its clients, survive it.
  defp attempt(operation, document_id, fun) do
    {:ok, timed(operation, document_id, fun)}
  rescue
    error ->
      Logger.error(
        "#{operation} failed for document #{document_id}: " <>
          Exception.format(:error, error, __STACKTRACE__)
      )

      :error
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
