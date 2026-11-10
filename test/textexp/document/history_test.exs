defmodule Textexp.Document.HistoryTest do
  use Textexp.DataCase

  alias Textexp.Fixtures

  alias Textexp.Document
  alias Textexp.Document.{History, Update}
  alias Textexp.SqliteRepo, as: Repo

  @now ~U[2026-11-10 12:00:00.000000Z]

  setup do
    %{document: Fixtures.create_document!(Fixtures.register_user(), %{title: "Notes"})}
  end

  # A document being written, whose edits come as updates, as from the editor.
  defp source, do: Yex.Doc.new()

  # Appends `text` to `source` and returns the update of that edit only.
  defp write(source, text) do
    before = Yex.encode_state_vector!(source)
    t = Yex.Doc.get_text(source, "t")
    Yex.Text.insert(t, Yex.Text.length(t), text)
    Yex.encode_state_as_update!(source, before)
  end

  defp text(nil), do: ""

  defp text(state) do
    doc = Yex.Doc.new()
    Yex.apply_update(doc, state)
    doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()
  end

  defp content(document), do: document.id |> Document.get_document!() |> Map.get(:snapshot)

  # Appends `text` as edited `seconds_ago` before @now.
  defp append(document, source, text, seconds_ago) do
    at = DateTime.add(@now, -seconds_ago)
    History.append(document.id, write(source, text), nil, at, at)
  end

  defp updates(document),
    do: Repo.all(from u in Update, where: u.document_id == ^document.id, order_by: u.id)

  test "the content is the snapshot plus the updates appended", %{document: document} do
    s = source()
    append(document, s, "a", 10)
    History.compact(document.id, @now)
    append(document, s, "b", 5)

    assert Repo.get!(Document.Document, document.id).snapshot |> text() == "a"
    assert content(document) |> text() == "ab"
  end

  test "appending saves the excerpt and the date of the edit", %{document: document} do
    at = DateTime.add(@now, -3)
    saved = History.append(document.id, write(source(), "a"), "a", at, at)

    assert saved.updated_at == at
    assert Repo.get!(Document.Document, document.id).excerpt == "a"
  end

  test "appending to a document deleted for good does nothing", %{document: document} do
    Document.delete_document(document.id)

    refute History.append(document.id, write(source(), "a"), "a")
    assert Repo.all(Update) == []
  end

  test "compacting folds the updates into the snapshot", %{document: document} do
    s = source()
    for {text, ago} <- [{"a", 30}, {"b", 20}, {"c", 10}], do: append(document, s, text, ago)

    History.compact(document.id, @now)

    stored = Repo.get!(Document.Document, document.id)
    assert text(stored.snapshot) == "abc"
    assert stored.snapshot_update_id == List.last(updates(document)).id
    assert History.pending_count(document.id) == 0
  end

  test "the snapshot is not written over a newer one", %{document: document} do
    s = source()
    append(document, s, "a", 10)
    History.compact(document.id, @now)
    stored = Repo.get!(Document.Document, document.id)

    # another node's compaction moved the snapshot on meanwhile
    Repo.update_all(from(d in Document.Document, where: d.id == ^document.id),
      set: [snapshot_update_id: stored.snapshot_update_id + 1000]
    )

    append(document, s, "b", 5)
    History.compact(document.id, @now)

    assert Repo.get!(Document.Document, document.id).snapshot |> text() == "a"
  end

  test "updates in the same range of time are merged once folded", %{document: document} do
    s = source()
    # three in the same minute, less than an hour ago, then one in the next
    # minute
    now = ~U[2026-11-10 12:00:59.000000Z]
    for {text, ago} <- [{"a", 50}, {"b", 40}, {"c", 30}], do: append(document, s, text, ago + 60)
    append(document, s, "d", 10)

    History.compact(document.id, now)

    assert [first, second] = updates(document)
    assert first.started_at == DateTime.add(@now, -110)
    assert first.ended_at == DateTime.add(@now, -90)
    assert second.ended_at == DateTime.add(@now, -10)
    assert Repo.get!(Document.Document, document.id).snapshot_update_id == second.id
    assert History.state_at(document.id, first.id) |> text() == "abc"
    assert content(document) |> text() == "abcd"
  end

  test "older updates are merged in coarser ranges", %{document: document} do
    s = source()
    # minutes apart, two hours ago: merged by the hour
    for {text, ago} <- [{"a", 7_500}, {"b", 7_400}, {"c", 7_300}],
        do: append(document, s, text, ago)

    History.compact(document.id, @now)

    assert [update] = updates(document)
    assert History.state_at(document.id, update.id) |> text() == "abc"
  end

  test "updates of more than 30 days ago are merged by the week", %{document: document} do
    s = source()
    # days apart, in the same week, two months ago
    week = 7 * 86_400
    start = div(DateTime.to_unix(@now) - 60 * 86_400, week) * week

    for {text, day} <- [{"a", 1}, {"b", 2}, {"c", 3}] do
      at = DateTime.from_unix!(start + day * 86_400, :second) |> DateTime.add(0, :microsecond)
      History.append(document.id, write(s, text), nil, at, at)
    end

    History.compact(document.id, @now)

    assert [_] = updates(document)
    assert content(document) |> text() == "abc"
  end

  test "updates not yet folded are not merged", %{document: document} do
    s = source()
    append(document, s, "a", 30)
    append(document, s, "b", 20)

    History.thin(document.id, @now)

    assert length(updates(document)) == 2
  end

  test "the versions are the ranges of time, the last first", %{document: document} do
    s = source()
    now = ~U[2026-11-10 12:00:59.000000Z]
    append(document, s, "a", 110)
    append(document, s, "b", 100)
    append(document, s, "c", 10)

    assert [last, first] = History.versions(document.id, now)
    assert first.started_at == DateTime.add(@now, -110)
    assert first.ended_at == DateTime.add(@now, -100)
    assert History.state_at(document.id, first.id) |> text() == "ab"
    assert History.state_at(document.id, last.id) |> text() == "abc"
  end

  test "an update of another document is no version of this one", %{document: document} do
    other = Fixtures.create_document!(Fixtures.register_user(), %{title: "Other"})
    History.append(other.id, write(source(), "x"), nil)
    [update] = updates(other)

    refute History.state_at(document.id, update.id)
  end

  test "an imported document starts its history", %{document: document} do
    {:ok, imported} =
      Document.import_document(
        Repo.preload(document, :owner).owner,
        "Imported",
        write(source(), "a")
      )

    assert [version] = History.versions(imported.id)
    assert History.state_at(imported.id, version.id) |> text() == "a"
    assert History.pending_count(imported.id) == 0
  end

  describe "for a user" do
    test "the readers list the versions and read them", %{document: document} do
      owner = Repo.preload(document, :owner).owner
      viewer = Fixtures.confirmed_user()
      Fixtures.share!(owner, document, viewer, :viewer)
      append(document, source(), "a", 10)

      assert {:ok, [version]} = Document.list_versions(document.id, viewer)
      assert {:ok, state} = Document.version_state(document.id, version.id, viewer)
      assert text(state) == "a"
    end

    test "the others do not", %{document: document} do
      append(document, source(), "a", 10)
      [version] = History.versions(document.id)
      stranger = Fixtures.register_user()

      assert Document.list_versions(document.id, stranger) == {:error, :forbidden}
      assert Document.version_state(document.id, version.id, stranger) == {:error, :forbidden}
    end

    test "a version merged since is not found", %{document: document} do
      owner = Repo.preload(document, :owner).owner

      assert Document.version_state(document.id, 123_456, owner) == {:error, :not_found}
    end
  end
end
