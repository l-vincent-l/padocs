defmodule PadocsWeb.HealthControllerTest do
  use PadocsWeb.ConnCase, async: true

  test "GET /health answers once the database does", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert response(conn, 200) == "ok"
  end
end
