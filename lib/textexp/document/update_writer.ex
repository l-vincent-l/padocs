defmodule Textexp.Document.UpdateWriter do
  @moduledoc """
  Appends the updates of all the documents being edited to their logs (see
  `Textexp.Document.History`), in one multi-row `INSERT` about every second,
  rather than one per document: the DocServers no longer wait on the
  database, and on libSQL one HTTP round trip carries the edits of all of
  them.

  - `append/4` hands over an update, without waiting: the DocServer goes on
    serving its clients;
  - every `:interval_ms` (1 s by default), the updates received are written,
    in the order received, so that those of a document keep their order;
  - `sync/0` writes them at once, e.g. before a DocServer folds its log into
    its snapshot when it stops;
  - on shutdown, it writes what is left: it is started before the DocServers'
    supervisor, so stopped after it, once they have all handed over their
    last edits.

  A failed write (e.g. the database busy) is logged and tried again at the
  next one; the updates of documents deleted meanwhile are dropped. After a
  crash of the node, the edits of the last second or two are missing from
  the database; the Yjs clients send them again when they resync.
  """
  use GenServer

  require Logger

  import Ecto.Query

  alias Textexp.Document.{Document, Update}
  alias Textexp.SqliteRepo, as: Repo

  # SQLite allows 32,766 parameters per statement, 4 per row
  @chunk_size 1_000
  @slow_ms 200

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Hands over `data`, an update of the content of the document of `id` made
  between `started_at` and `ended_at`, to be appended at the next write.
  """
  def append(server \\ __MODULE__, id, data, started_at, ended_at) do
    GenServer.cast(server, {:append, id, data, started_at, ended_at})
  end

  @doc """
  Writes the updates received so far: `:ok`, or `:error` if the write
  failed (they are kept for the next one).
  """
  def sync(server \\ __MODULE__) do
    GenServer.call(server, :sync, :infinity)
  end

  @impl true
  def init(opts) do
    # to write what is left on shutdown
    Process.flag(:trap_exit, true)
    interval = Keyword.get(opts, :interval_ms, 1_000)
    schedule(interval)
    {:ok, %{interval: interval, pending: []}}
  end

  @impl true
  def handle_cast({:append, id, data, started_at, ended_at}, state) do
    row = %{document_id: id, data: data, started_at: started_at, ended_at: ended_at}
    {:noreply, %{state | pending: [row | state.pending]}}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    state = write(state)
    {:reply, if(state.pending == [], do: :ok, else: :error), state}
  end

  @impl true
  def handle_info(:write, state) do
    schedule(state.interval)
    {:noreply, write(state)}
  end

  @impl true
  def terminate(_reason, state) do
    state = write(state)

    if state.pending != [] do
      Logger.error("#{length(state.pending)} document updates not saved on stopping")
    end
  end

  defp schedule(interval), do: Process.send_after(self(), :write, interval)

  defp write(%{pending: []} = state), do: state

  defp write(state) do
    rows = Enum.reverse(state.pending)
    start = System.monotonic_time()
    left = insert(rows)
    duration = System.monotonic_time() - start

    :telemetry.execute(
      [:textexp, :update_writer, :stop],
      %{duration: duration, rows: length(rows) - length(left), failed: length(left)},
      %{}
    )

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    if duration_ms >= @slow_ms do
      {:message_queue_len, queue} = Process.info(self(), :message_queue_len)

      Logger.warning(
        "Slow write of #{length(rows)} document updates: #{duration_ms} ms " <>
          "(#{queue} messages waiting)"
      )
    end

    %{state | pending: Enum.reverse(left)}
  end

  # The rows not written, in order: those of the chunk that failed and after,
  # less those of documents deleted meanwhile.
  defp insert([]), do: []

  defp insert(rows) do
    rows
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce_while(0, fn chunk, written ->
      try do
        Repo.insert_all(Update, chunk)
        {:cont, written + length(chunk)}
      rescue
        error ->
          Logger.error(
            "Writing #{length(chunk)} document updates failed: " <>
              Exception.format(:error, error, __STACKTRACE__)
          )

          {:halt, written}
      end
    end)
    |> then(fn written ->
      left = Enum.drop(rows, written)
      kept = if left == [], do: [], else: existing(left)

      # fewer: those of deleted documents made it fail, tried again without
      if length(kept) < length(left), do: insert(kept), else: kept
    end)
  end

  # `rows` less those whose document no longer exists, which would fail the
  # whole statement again; all of them if that cannot be told.
  defp existing(rows) do
    ids = rows |> Enum.map(& &1.document_id) |> Enum.uniq()
    found = Repo.all(from d in Document, where: d.id in ^ids, select: d.id) |> MapSet.new()
    {kept, dropped} = Enum.split_with(rows, &MapSet.member?(found, &1.document_id))

    if dropped != [] do
      Logger.warning("Dropped #{length(dropped)} updates of deleted documents")
    end

    kept
  rescue
    _ -> rows
  end
end
