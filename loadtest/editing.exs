# Editors in documents: every virtual user (VU) signs in as one of the
# accounts of loadtest/seed.exs, joins the channel of one of the documents as
# the editor does (y-phoenix-channel), syncs, then types a word every second
# or so, for 2 minutes, before leaving and joining again. The VUs are spread
# over the documents in turn (VU 1 in the first, VU 2 in the second...), or
# with LOADTEST_PER_DOCUMENT, that many in each (VUs 1 to 5 in the first, 6
# to 10 in the second...), so that more VUs make more documents in use.
#
# The VUs of a document go through its one DocServer, which applies every
# edit and sends it to all the others.
#
# With LOADTEST_WRITERS, only that many VUs type in each document (the first
# ones to join it); the others read.
#
# Measures, besides Stampede's own (`ws.connect`, `channel.join`):
#
#   * `yjs.sync` - from asking for the document (sync step 1) to having it
#     (step 2), on joining
#   * `yjs.propagation` - from a VU's edit to its arrival at another VU. Each
#     edit also writes the time it was made under the VU's key in a Y.Map,
#     read back by the VUs that receive it. All the VUs run on this machine,
#     so their clocks agree.
#   * `yjs.edits` and `yjs.received` - counts of updates sent, and received
#     by the observers
#
# Only the first VUs, the observers, read the updates of the others: with all
# of them doing it, the load test would spend more time applying updates than
# the server spends sending them. The others keep only the sync messages and
# let the rest be counted (`channel.messages`), which loads the server the
# same.
#
# Run with loadtest/app.sh, which starts the application and seeds it:
#
#   LOADTEST_DOCUMENTS=<ids> mix stampede.run loadtest/editing.exs
#
# Environment: LOADTEST_URL (http://localhost:4000), LOADTEST_DOCUMENTS (the
# ids printed by the seed, separated by commas), LOADTEST_USERS (50: how many
# accounts the seed made; VUs beyond that share them), LOADTEST_OBSERVERS
# (10), LOADTEST_WRITERS (all), LOADTEST_PER_DOCUMENT, LOADTEST_TYPING_MS (1000: the time between two
# words, give or take half).
Code.require_file("session.exs", __DIR__)

defmodule Loadtest.Editing do
  use Stampede.Scenario

  alias Loadtest.Session

  # How long a VU stays in the document before leaving and joining again
  @session_ms 120_000
  @words ~w(le la les un une de du et à texte document charge réunion projet note)

  @impl true
  def options do
    [
      stages: [{[second: 30], 50}, {[minute: 2], 50}, {[second: 10], 0}],
      thresholds: [
        {"channel.join", p95: 500},
        {"yjs.sync", p95: 500},
        {"yjs.propagation", p95: 250},
        {"iteration.errors", count: 0}
      ]
    ]
  end

  # Signs in every account once, before the load: bcrypt makes a sign-in
  # costly, and it is not what is measured here.
  @impl true
  def setup(_opts) do
    url = Session.url()
    documents = Session.documents()
    sessions = Session.sign_in_all(url, elem(documents, 0))

    %{
      url: url,
      documents: documents,
      sessions: sessions,
      observers: Session.env_integer("LOADTEST_OBSERVERS", 10),
      writers: Session.env_integer("LOADTEST_WRITERS", nil),
      per_document: Session.env_integer("LOADTEST_PER_DOCUMENT", nil),
      typing_ms: Session.env_integer("LOADTEST_TYPING_MS", 1_000)
    }
  end

  @impl true
  def run(vu) do
    %{url: url, documents: documents, sessions: sessions} = vu.data
    session = Session.for_vu(sessions, vu.id)
    {document, rank} = place(vu.id, tuple_size(documents), vu.data.per_document)
    topic = "y_doc_room:#{elem(documents, document)}"
    writer? = vu.data.writers == nil or rank < vu.data.writers

    observer? = vu.id <= vu.data.observers

    {:ok, socket} =
      Stampede.Channels.connect(String.replace(url, ~r/^http/, "ws") <> "/socket",
        params: %{"_csrf_token" => session.csrf_token, "vsn" => "2.0.0"},
        headers: [{"cookie", session.cookie}],
        keep: if(observer?, do: nil, else: &sync_message?/1)
      )

    {:ok, _reply} = Stampede.Channels.join(socket, topic)

    doc = Yex.Doc.new()

    state = %{
      socket: socket,
      topic: topic,
      doc: doc,
      key: "vu-#{vu.id}",
      seen: %{},
      observer?: observer?,
      typing_ms: vu.data.typing_ms
    }

    state = sync(state)
    stop_at = now() + @session_ms
    # a VU that only reads never reaches its next word
    next_word_at = if writer?, do: now() + next_word_in(state), else: stop_at
    loop(state, next_word_at, stop_at)
  end

  # The index of the VU's document, and the VU's rank among those of the
  # document: the documents in turn, or filled `per_document` at a time.
  defp place(id, documents, nil), do: {rem(id - 1, documents), div(id - 1, documents)}

  defp place(id, documents, per_document),
    do: {rem(div(id - 1, per_document), documents), rem(id - 1, per_document)}

  # Sync step 1 and 2: what a VU that is not an observer keeps of the messages
  # it receives.
  defp sync_message?({:binary, <<0, step, _::binary>>}), do: step in [0, 1]
  defp sync_message?(_payload), do: false

  # Sync step 1 with the document's state vector (empty); the server answers
  # with its step 2, the whole document, and its own step 1, answered here.
  defp sync(state) do
    started_at = System.monotonic_time()
    {:ok, step1} = Yex.Sync.get_sync_step1(state.doc)
    send_message(state, "yjs_sync", {:sync, step1})

    state = receive_until(state, :step2, now() + 5_000)
    Stampede.record("yjs.sync", System.monotonic_time() - started_at, :native)
    state
  end

  # Receives the updates of the others until it is time for the next word,
  # types it, and starts again, until the session ends.
  defp loop(state, next_word_at, stop_at) do
    cond do
      now() >= stop_at ->
        :ok

      now() >= next_word_at ->
        type_word(state)
        loop(state, now() + next_word_in(state), stop_at)

      state.observer? ->
        state |> receive_until(:any, next_word_at) |> loop(next_word_at, stop_at)

      true ->
        Process.sleep(max(next_word_at - now(), 0))
        loop(state, next_word_at, stop_at)
    end
  end

  # Waits for messages until `deadline`, or, with `:step2`, until the sync
  # step 2 arrives.
  defp receive_until(state, until, deadline) do
    case Stampede.Channels.await(state.socket, state.topic, "yjs", max(deadline - now(), 0)) do
      {:ok, {:binary, message}} ->
        {state, kind} = handle_message(state, message)

        if until == :step2 and kind == :step2,
          do: state,
          else: receive_until(state, until, deadline)

      {:error, :timeout} when until == :any ->
        state

      {:error, reason} ->
        raise "no message from the document: #{inspect(reason)}"
    end
  end

  defp handle_message(state, message) do
    case Yex.Sync.message_decode!(message) do
      {:sync, {:sync_step1, state_vector}} ->
        {:ok, step2} = Yex.Sync.get_sync_step2(state.doc, state_vector)
        send_message(state, "yjs", {:sync, step2})
        {state, :step1}

      {:sync, {:sync_step2, update}} ->
        :ok = Yex.apply_update(state.doc, update)
        {%{state | seen: pings(state)}, :step2}

      {:sync, {:sync_update, update}} ->
        :ok = Yex.apply_update(state.doc, update)
        Stampede.increment("yjs.received")
        {record_propagation(state), :update}

      _awareness_or_else ->
        {state, :other}
    end
  end

  # The times of the edits received since the last ones, the VU's own aside.
  defp record_propagation(state) do
    pings = pings(state)
    received_at = System.os_time(:millisecond)

    for {key, sent_at} <- pings, key != state.key, state.seen[key] != sent_at do
      Stampede.record("yjs.propagation", max(received_at - trunc(sent_at), 0), :millisecond)
    end

    %{state | seen: pings}
  end

  defp pings(state), do: state.doc |> Yex.Doc.get_map("loadtest") |> Yex.Map.to_map()

  # A word inserted somewhere in the paragraph, and the time in the VU's key,
  # sent as one update.
  defp type_word(state) do
    {:ok, before} = Yex.encode_state_vector(state.doc)

    Yex.Doc.transaction(state.doc, fn ->
      text = paragraph_text(state.doc)
      word = Enum.random(@words) <> " "
      Yex.XmlText.insert(text, :rand.uniform(Yex.XmlText.length(text) + 1) - 1, word)

      state.doc
      |> Yex.Doc.get_map("loadtest")
      |> Yex.Map.set(state.key, System.os_time(:millisecond))
    end)

    {:ok, update} = Yex.encode_state_as_update(state.doc, before)
    send_message(state, "yjs", {:sync, {:sync_update, update}})
    Stampede.increment("yjs.edits")
  end

  # The text of the seed's paragraph: blockGroup > blockContainer > paragraph.
  defp paragraph_text(doc) do
    fragment = Yex.Doc.get_xml_fragment(doc, "document-store")
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    {:ok, container} = Yex.XmlElement.fetch(group, 0)
    {:ok, paragraph} = Yex.XmlElement.fetch(container, 0)
    {:ok, text} = Yex.XmlElement.fetch(paragraph, 0)
    text
  end

  defp send_message(state, event, message) do
    Stampede.Channels.cast(
      state.socket,
      state.topic,
      event,
      {:binary, Yex.Sync.message_encode!(message)}
    )
  end

  defp next_word_in(state), do: div(state.typing_ms, 2) + :rand.uniform(state.typing_ms)
  defp now, do: System.monotonic_time(:millisecond)
end
