defmodule Padocs.Document.SnapshotTest do
  use Padocs.DataCase

  alias Padocs.Fixtures

  alias Padocs.Document

  # Valid UTF-8 containing a NUL byte: stored as TEXT, SQLite would truncate it
  # at the NUL (it happened with ecto_libsql, about one Yjs update in 50).
  @utf8_with_nul <<"abc", 0, "def">>

  setup do
    %{document: Fixtures.create_document!(Fixtures.register_user())}
  end

  test "snapshots keep UTF-8 binaries containing NUL bytes intact", %{document: document} do
    Document.History.append(document.id, @utf8_with_nul, nil)

    assert Document.get_document!(document.id).snapshot == @utf8_with_nul
  end
end
