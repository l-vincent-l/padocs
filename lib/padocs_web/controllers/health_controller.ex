defmodule PadocsWeb.HealthController do
  @moduledoc """
  The health check of the hosts that wait for a new container to be ready
  before sending it traffic (Kamal, Dokku, Render): 200 once the database
  answers, 503 otherwise. Served over plain HTTP too (excluded from
  `force_ssl` in config/prod.exs), as those checks reach the container directly.
  """
  use PadocsWeb, :controller

  def show(conn, _params) do
    case Padocs.SqliteRepo.query("SELECT 1") do
      {:ok, _} -> send_resp(conn, 200, "ok")
      {:error, _} -> send_resp(conn, 503, "database unavailable")
    end
  end
end
