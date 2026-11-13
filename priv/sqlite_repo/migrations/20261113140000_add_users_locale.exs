defmodule Padocs.SqliteRepo.Migrations.AddUsersLocale do
  @moduledoc """
  The language a user chose for the interface and the emails (`"fr"`,
  `"en"`), `nil` until they choose: their browser's then (see
  `PadocsWeb.Locale`).
  """
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :locale, :string
    end
  end
end
