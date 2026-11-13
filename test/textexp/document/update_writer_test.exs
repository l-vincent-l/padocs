defmodule Textexp.Document.UpdateWriterTest do
  use Textexp.DataCase

  import ExUnit.CaptureLog

  alias Textexp.Fixtures

  alias Textexp.Document
  alias Textexp.Document.{Update, UpdateWriter}
  alias Textexp.SqliteRepo, as: Repo

  setup do
    owner = Fixtures.register_user()
    # its own, written only on sync: the timer does not fire during a test
    writer = start_supervised!({UpdateWriter, name: nil, interval_ms: :timer.hours(1)})

    %{
      writer: writer,
      first: Fixtures.create_document!(owner, %{title: "First"}),
      second: Fixtures.create_document!(owner, %{title: "Second"})
    }
  end

  defp update(text) do
    doc = Yex.Doc.new()
    doc |> Yex.Doc.get_text("t") |> Yex.Text.insert(0, text)
    Yex.encode_state_as_update!(doc)
  end

  defp append(writer, document, text) do
    now = DateTime.utc_now()
    UpdateWriter.append(writer, document.id, update(text), now, now)
  end

  defp texts(document) do
    from(u in Update, where: u.document_id == ^document.id, order_by: u.id, select: u.data)
    |> Repo.all()
    |> Enum.map(fn data ->
      doc = Yex.Doc.new()
      Yex.apply_update(doc, data)
      doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()
    end)
  end

  test "appending does not write until the next write", %{writer: writer, first: first} do
    append(writer, first, "a")
    assert texts(first) == []

    assert UpdateWriter.sync(writer) == :ok
    assert texts(first) == ["a"]
  end

  test "writes the updates of all the documents, in their order",
       %{writer: writer, first: first, second: second} do
    test_pid = self()
    handler_id = "update-writer-test-#{inspect(test_pid)}"

    :telemetry.attach(
      handler_id,
      [:textexp, :update_writer, :stop],
      fn _event, measurements, _metadata, _config -> send(test_pid, {:written, measurements}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    append(writer, first, "a")
    append(writer, second, "x")
    append(writer, first, "b")

    assert UpdateWriter.sync(writer) == :ok
    assert texts(first) == ["a", "b"]
    assert texts(second) == ["x"]
    # one write for all of them
    assert_received {:written, %{rows: 3, failed: 0}}
  end

  test "drops the updates of a document deleted meanwhile, and writes the others",
       %{writer: writer, first: first, second: second} do
    append(writer, first, "a")
    append(writer, second, "x")
    Repo.delete!(%Document.Document{id: first.id})

    log =
      capture_log(fn ->
        assert UpdateWriter.sync(writer) == :ok
      end)

    assert log =~ "Dropped 1 updates of deleted documents"
    assert texts(second) == ["x"]
    assert Repo.aggregate(from(u in Update, where: u.document_id == ^first.id), :count) == 0
  end

  test "writes what is left when stopped", %{first: first} do
    writer =
      start_supervised!({UpdateWriter, name: nil, interval_ms: :timer.hours(1)}, id: :other)

    append(writer, first, "a")

    stop_supervised!(:other)

    assert texts(first) == ["a"]
  end
end
