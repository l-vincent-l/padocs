defmodule Padocs.SqliteRepo.Migrations.ConvertUuidsToText do
  @moduledoc """
  Rewrites the UUIDs stored as 16-byte BLOBs by ecto_libsql, the previous
  adapter, as the text that ecto_sqlite3 stores and queries
  (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, lowercase). ecto_libsql stored some
  of them as text already: those are left as they are.
  """
  use Ecto.Migration

  @columns [users: [:id], documents: [:id, :owner_id]]

  def up do
    # documents.owner_id references users.id: checked at commit, once both
    # sides are rewritten.
    execute "PRAGMA defer_foreign_keys = ON"

    for {table, columns} <- @columns, column <- columns do
      execute """
      UPDATE #{table} SET #{column} = #{uuid_text(column)} WHERE typeof(#{column}) = 'blob'
      """
    end
  end

  # The text form works with both adapters: nothing to undo.
  def down, do: :ok

  defp uuid_text(column) do
    hex = "lower(hex(#{column}))"

    Enum.map_join([{1, 8}, {9, 4}, {13, 4}, {17, 4}, {21, 12}], " || '-' || ", fn {from, length} ->
      "substr(#{hex}, #{from}, #{length})"
    end)
  end
end
