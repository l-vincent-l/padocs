# Many editors in one document: every virtual user (VU) signs in as one of
# the accounts of loadtest/seed.exs, joins the document's channel as the
# editor does (y-phoenix-channel), syncs, then types a word every second or
# so, for 2 minutes, before leaving and joining again.
#
# All the VUs go through the document's one DocServer, which applies every
# edit and sends it to all the others: its mailbox is the expected limit.
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
#   LOADTEST_DOCUMENT=<id> mix stampede.run loadtest/one_document.exs
#
# Environment: LOADTEST_URL (http://localhost:4000), LOADTEST_DOCUMENT (the
# id printed by the seed), LOADTEST_USERS (50: how many accounts the seed
# made; VUs beyond that share them), LOADTEST_OBSERVERS (10).
defmodule Loadtest.OneDocument do
  use Stampede.Scenario

  @password "loadtest-password"
  # How long a VU stays in the document before leaving and joining again
  @session_ms 120_000
  # Time between two words typed by a VU, give or take half
  @typing_ms 1_000
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
    {:ok, _apps} = Application.ensure_all_started(:req)
    url = System.get_env("LOADTEST_URL", "http://localhost:4000")

    document =
      System.get_env("LOADTEST_DOCUMENT") ||
        raise "LOADTEST_DOCUMENT is missing: the id printed by loadtest/seed.exs"

    users = String.to_integer(System.get_env("LOADTEST_USERS", "50"))
    observers = String.to_integer(System.get_env("LOADTEST_OBSERVERS", "10"))

    sessions =
      1..users
      |> Task.async_stream(&sign_in(url, document, &1), max_concurrency: 4, timeout: 60_000)
      |> Enum.map(fn {:ok, session} -> session end)
      |> List.to_tuple()

    %{url: url, document: document, sessions: sessions, observers: observers}
  end

  # The session cookie of the account, and the CSRF token of the document's
  # page, which the socket asks for to read the session.
  defp sign_in(url, document, i) do
    req = Req.new(base_url: url, redirect: false, retry: false)

    page = Req.get!(req, url: "/sign-in")
    cookie = session_cookie(page, nil)

    response =
      Req.post!(req,
        url: "/sign-in",
        headers: [cookie: cookie],
        form: [
          _csrf_token: csrf_token(page.body),
          "user[email]": "loadtest-#{i}@example.com",
          "user[password]": @password
        ]
      )

    if response.status != 302, do: raise("sign-in of loadtest-#{i} failed: #{response.status}")
    cookie = session_cookie(response, cookie)

    page = Req.get!(req, url: "/documents/#{document}", headers: [cookie: cookie])
    if page.status != 200, do: raise("document page for loadtest-#{i}: #{page.status}")

    %{cookie: session_cookie(page, cookie), csrf_token: csrf_token(page.body)}
  end

  defp session_cookie(response, previous) do
    response
    |> Req.Response.get_header("set-cookie")
    |> Enum.find_value(previous, fn header ->
      case Regex.run(~r/^(_textexp_key=[^;]+)/, header) do
        [_, cookie] -> cookie
        nil -> nil
      end
    end)
  end

  defp csrf_token(html) do
    [_, token] = Regex.run(~r/<meta name="csrf-token" content="([^"]+)"/, html)
    token
  end

  @impl true
  def run(vu) do
    %{url: url, document: document, sessions: sessions} = vu.data
    session = elem(sessions, rem(vu.id - 1, tuple_size(sessions)))
    topic = "y_doc_room:#{document}"

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
      observer?: observer?
    }

    state = sync(state)
    stop_at = now() + @session_ms
    loop(state, now() + next_word_in(), stop_at)
  end

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
        loop(state, now() + next_word_in(), stop_at)

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

  defp next_word_in, do: div(@typing_ms, 2) + :rand.uniform(@typing_ms)
  defp now, do: System.monotonic_time(:millisecond)
end
