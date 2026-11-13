defmodule PadocsWeb.DashboardAuthTest do
  # changes the application env
  use PadocsWeb.ConnCase, async: false

  setup do
    previous = Application.get_env(:padocs, :dashboard_auth)
    on_exit(fn -> Application.put_env(:padocs, :dashboard_auth, previous) end)
  end

  defp put_credentials(username, password) do
    Application.put_env(:padocs, :dashboard_auth, username: username, password: password)
  end

  test "is not found without credentials configured", %{conn: conn} do
    put_credentials(nil, nil)
    assert get(conn, "/admin/dashboard").status == 404
  end

  test "asks for the credentials", %{conn: conn} do
    put_credentials("admin", "secret")
    assert get(conn, "/admin/dashboard").status == 401
  end

  test "rejects wrong credentials", %{conn: conn} do
    put_credentials("admin", "secret")

    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("admin", "wrong"))
      |> get("/admin/dashboard")

    assert conn.status == 401
  end

  test "opens with the credentials", %{conn: conn} do
    put_credentials("admin", "secret")

    conn =
      conn
      |> put_req_header("authorization", Plug.BasicAuth.encode_basic_auth("admin", "secret"))
      |> get("/admin/dashboard")

    assert redirected_to(conn) =~ "/admin/dashboard/home"
  end
end
