defmodule Textexp.Document.SearchIndex do
  @moduledoc """
  Holds the search index of all the documents (see `Textexp.Document.Search`)
  and keeps it up to date:

  - when started, it indexes all the documents, in the background (unless
    `build: false`, as in the tests, which start without database): until it
    is done, searches find fewer documents;
  - `changed/1` tells it (on every node) that a document's title, body or tags changed, or
    that it was deleted, without waiting: e.g. its excerpt saved, about every
    10 s while it is being edited (see `Textexp.Document.History`);
  - every `:interval_ms` (5 s by default), it reads the documents that
    changed from the database and indexes them again, with one commit, the
    costly part, for all of them;
  - `sync/0` does it at once.

  It is the only writer of the index; searches read it from their own
  process (`index/0`), concurrently. A failed update is logged and tried
  again at the next one. The index is in native memory, rebuilt at each
  start: a document deleted with its parent stays in it until then, but is
  never found, as nobody can read it.
  """
  use GenServer

  require Logger

  alias Textexp.Document.Search

  @key {__MODULE__, :index}
  @topic "search_index"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "The index, for searches; `nil` before it is started."
  def index, do: :persistent_term.get(@key, nil)

  @doc """
  Tells that the document of `id` changed, to index it again at the next
  update. Broadcast: each node of a cluster has its own index.
  """
  def changed(id), do: Phoenix.PubSub.broadcast(Textexp.PubSub, @topic, {@topic, id})

  @doc """
  Indexes the documents changed so far: `:ok`, or `:error` if it failed
  (they are kept for the next update).
  """
  def sync, do: GenServer.call(__MODULE__, :sync, :infinity)

  @impl true
  def init(opts) do
    {:ok, index, writer} = Search.new_index()
    :ok = Phoenix.PubSub.subscribe(Textexp.PubSub, @topic)
    # Put once per start: changing a persistent term costs a global GC
    :persistent_term.put(@key, index)

    state = %{
      writer: writer,
      pending: MapSet.new(),
      interval_ms: Keyword.get(opts, :interval_ms, 5_000),
      timer: nil
    }

    if Keyword.get(opts, :build, true),
      do: {:ok, state, {:continue, :build}},
      else: {:ok, state}
  end

  @impl true
  def handle_continue(:build, state) do
    {us, result} = :timer.tc(fn -> Search.index_all(state.writer) end)

    case result do
      :ok -> Logger.info("Search index built in #{div(us, 1000)} ms")
      error -> Logger.error("Search index not built: #{inspect(error)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({@topic, id}, state) do
    timer = state.timer || Process.send_after(self(), :update, state.interval_ms)
    {:noreply, %{state | pending: MapSet.put(state.pending, id), timer: timer}}
  end

  def handle_info(:update, state) do
    {_result, state} = update(%{state | timer: nil})
    {:noreply, state}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    {result, state} = update(%{state | timer: nil})
    {:reply, result, state}
  end

  defp update(state) do
    if Enum.empty?(state.pending) do
      {:ok, state}
    else
      ids = MapSet.to_list(state.pending)

      result =
        try do
          Search.index_documents(state.writer, ids)
        rescue
          error -> {:error, error}
        end

      case result do
        :ok ->
          {:ok, %{state | pending: MapSet.new()}}

        error ->
          Logger.warning("Search index not updated, tried again later: #{inspect(error)}")
          timer = Process.send_after(self(), :update, state.interval_ms)
          {:error, %{state | timer: timer}}
      end
    end
  end
end
