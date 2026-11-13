defmodule Padocs.Document.History do
  @moduledoc """
  The Yjs log of a document, which is also its history.

  The DocServer appends the edits of about a second, merged into one update,
  through `Padocs.Document.UpdateWriter`, which writes those of all the
  documents at once (see `Padocs.Document.YPersistence`), and saves the
  excerpt of the document less often (`save_excerpt/3`). Appending never
  overwrites: two DocServers of a document, on two nodes, cannot lose each
  other's edits.

  The document's `snapshot` caches the merged state of the updates up to its
  `snapshot_update_id`: its content is that snapshot plus the updates after
  it (`content/1`). The compaction (`compact/2`) folds those updates into the
  snapshot, with a write conditional on `snapshot_update_id`, so that two
  compactions of the same document cannot overwrite each other.

  The updates are not deleted once folded: they are the history. The
  compaction merges those of the same range of time (`thin/2`), ranges
  coarser with age: a minute for the last hour, an hour for the last day, a
  day for the last 30 days, a week before. Replaying the updates up to one of
  them gives the document at the end of its range (`state_at/2`), each a
  point of its history (`versions/2`).

  These functions are done without user, for the DocServer; those of
  `Padocs.Document` check the reader's rights.
  """
  import Ecto.Query

  alias Padocs.Document.{Document, SearchIndex, Update}
  alias Padocs.SqliteRepo, as: Repo

  @minute 60
  @hour 3_600
  @day 86_400

  # {age below which, range}, in seconds
  @ranges [{@hour, @minute}, {@day, @hour}, {30 * @day, @day}, {:infinity, 7 * @day}]

  @doc """
  Appends `data`, an update of the content of the document of `id` made
  between `started_at` and `ended_at`, at once: one `INSERT`. The DocServer
  goes through `Padocs.Document.UpdateWriter` instead.
  """
  def append_update(id, data, started_at, ended_at) do
    Repo.insert!(%Update{document_id: id, data: data, started_at: started_at, ended_at: ended_at})
    :ok
  end

  @doc """
  Saves the `excerpt` of the document of `id`, edited last at `at`, which
  becomes its `updated_at`. A document saved without title, but with text,
  gets a dated one. Without text, it stays untitled so that it is deleted
  when left (see `YPersistence.unbind/3`). The search index is told, to
  index it again.

  The document saved, with its `title` and `updated_at`, or `nil` if it was
  deleted for good.
  """
  def save_excerpt(id, excerpt, at) do
    dated_title = "Notes du #{Calendar.strftime(DateTime.to_date(at), "%d-%m-%Y")}"

    case Repo.update_all(
           from(d in Document,
             where: d.id == ^id,
             update: [
               set: [
                 excerpt: ^excerpt,
                 updated_at: ^at,
                 # blank: NULL, or only spaces, tabs and line breaks
                 title:
                   fragment(
                     "CASE WHEN coalesce(trim(?, char(32, 9, 10, 13)), '') = '' AND ? IS NOT NULL THEN ? ELSE ? END",
                     d.title,
                     ^excerpt,
                     ^dated_title,
                     d.title
                   )
               ]
             ],
             select: struct(d, [:id, :title, :updated_at])
           ),
           []
         ) do
      {1, [document]} ->
        SearchIndex.changed(id)
        document

      {0, []} ->
        nil
    end
  end

  @doc """
  Appends `data` and saves `excerpt` (see `append_update/4` and
  `save_excerpt/3`): the document saved, or `nil` if it was deleted for
  good, nothing being appended then.
  """
  def append(id, data, excerpt, started_at \\ nil, ended_at \\ nil) do
    ended_at = ended_at || DateTime.utc_now()

    with %Document{} = document <- save_excerpt(id, excerpt, ended_at) do
      append_update(id, data, started_at || ended_at, ended_at)
      document
    end
  end

  @doc """
  The full Yjs state of `document`'s content: its snapshot plus the updates
  after it, `nil` for a document never written. `document` needs its
  `snapshot` and `snapshot_update_id`.
  """
  def content(%Document{} = document) do
    case tail(document.id, document.snapshot_update_id) do
      [] -> document.snapshot
      updates -> merge_state(Enum.reject([document.snapshot | updates], &is_nil/1))
    end
  end

  @doc """
  The full Yjs state of the content of each of `documents`, by id (see
  `content/1`), in one query for all their updates after their snapshots.
  """
  def contents([]), do: %{}

  def contents(documents) do
    tails =
      from(u in Update,
        join: d in Document,
        on: d.id == u.document_id and u.id > d.snapshot_update_id,
        where: d.id in ^Enum.map(documents, & &1.id),
        order_by: u.id,
        select: {u.document_id, u.data}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    Map.new(documents, fn document ->
      content =
        case Map.get(tails, document.id, []) do
          [] -> document.snapshot
          updates -> merge_state(Enum.reject([document.snapshot | updates], &is_nil/1))
        end

      {document.id, content}
    end)
  end

  @doc "The number of updates of the document of `id` not yet folded into its snapshot."
  def pending_count(id) do
    Repo.one(
      from u in Update,
        join: d in Document,
        on: d.id == u.document_id,
        where: u.document_id == ^id and u.id > d.snapshot_update_id,
        select: count()
    )
  end

  @doc """
  Folds the updates of the document of `id` appended since its snapshot into
  it, then merges the updates of the same range of time (see `thin/2`).
  The snapshot is only written if no other compaction wrote it meanwhile.
  """
  def compact(id, now \\ DateTime.utc_now()) do
    document =
      Repo.one(
        from d in Document,
          where: d.id == ^id,
          select: struct(d, [:id, :snapshot, :snapshot_update_id])
      )

    with %Document{} <- document,
         [_ | _] = updates <- Repo.all(tail_query(id, document.snapshot_update_id, [:id, :data])) do
      snapshot =
        merge_state(Enum.reject([document.snapshot | Enum.map(updates, & &1.data)], &is_nil/1))

      # One statement, conditional: not in a read-then-write transaction,
      # which SQLite fails at once (database is locked) when another
      # connection wrote meanwhile.
      Repo.update_all(
        from(d in Document,
          where: d.id == ^id and d.snapshot_update_id == ^document.snapshot_update_id
        ),
        set: [snapshot: snapshot, snapshot_update_id: List.last(updates).id]
      )
    end

    thin(id, now)
  end

  @doc """
  Merges the updates of the document of `id` already folded into its
  snapshot that fall in the same range of time (see the module doc), at
  `now`: each consecutive run of them becomes one update, keeping the id of
  its last, so that the snapshot still covers the same ones.
  """
  def thin(id, now \\ DateTime.utc_now()) do
    runs =
      from(u in Update,
        join: d in Document,
        on: d.id == u.document_id,
        where: u.document_id == ^id and u.id <= d.snapshot_update_id,
        order_by: u.id,
        select: struct(u, [:id, :started_at, :ended_at])
      )
      |> Repo.all()
      |> Enum.chunk_by(&range(&1.ended_at, now))
      |> Enum.filter(&match?([_, _ | _], &1))

    # Not in a transaction either: the merge is written before the updates
    # it replaces are deleted, so that, stopped in between, they are only
    # there twice, which Yjs ignores.
    for run <- runs do
      ids = Enum.map(run, & &1.id)
      last = List.last(ids)

      {:ok, data} =
        from(u in Update, where: u.id in ^ids, order_by: u.id, select: u.data)
        |> Repo.all()
        |> Yex.merge_updates()

      Repo.update_all(from(u in Update, where: u.id == ^last),
        set: [data: data, started_at: hd(run).started_at]
      )

      Repo.delete_all(from u in Update, where: u.id in ^(ids -- [last]))
    end

    length(runs)
  end

  @doc """
  The points of the history of the document of `id`, the last first:
  `%{id, started_at, ended_at}`, the end of a range of edits (see the module
  doc). The updates not yet merged are shown as merged.
  """
  def versions(id, now \\ DateTime.utc_now()) do
    from(u in Update,
      where: u.document_id == ^id,
      order_by: u.id,
      select: struct(u, [:id, :started_at, :ended_at])
    )
    |> Repo.all()
    |> Enum.chunk_by(&range(&1.ended_at, now))
    |> Enum.map(fn run ->
      last = List.last(run)
      %{id: last.id, started_at: hd(run).started_at, ended_at: last.ended_at}
    end)
    |> Enum.reverse()
  end

  @doc """
  The full Yjs state of the document of `id` once the update of
  `update_id` was applied, or `nil` if it has no such update.
  """
  def state_at(id, update_id) do
    if Repo.exists?(from u in Update, where: u.id == ^update_id and u.document_id == ^id) do
      from(u in Update,
        where: u.document_id == ^id and u.id <= ^update_id,
        order_by: u.id,
        select: u.data
      )
      |> Repo.all()
      |> merge_state()
    end
  end

  # The range of time an update ending at `ended_at` falls in, at `now`.
  defp range(ended_at, now) do
    age = DateTime.diff(now, ended_at)
    {_, size} = Enum.find(@ranges, fn {below, _} -> below == :infinity or age < below end)
    {size, div(DateTime.to_unix(ended_at), size)}
  end

  defp tail(id, after_id), do: Repo.all(tail_query(id, after_id, [:data])) |> Enum.map(& &1.data)

  defp tail_query(id, after_id, fields) do
    from u in Update,
      where: u.document_id == ^id and u.id > ^after_id,
      order_by: u.id,
      select: struct(u, ^fields)
  end

  # The state of a document made of `updates`, without the content they
  # delete (Yjs's garbage collection): smaller than their merge.
  defp merge_state([update]), do: update

  defp merge_state(updates) do
    doc = Yex.Doc.new()
    Yex.Doc.transaction(doc, fn -> Enum.each(updates, &Yex.apply_update(doc, &1)) end)
    Yex.encode_state_as_update!(doc)
  end
end
