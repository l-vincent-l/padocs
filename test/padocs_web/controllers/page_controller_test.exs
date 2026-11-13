defmodule PadocsWeb.PageControllerTest do
  use PadocsWeb.ConnCase

  test "GET / redirects to the documents", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/documents"
  end
end
