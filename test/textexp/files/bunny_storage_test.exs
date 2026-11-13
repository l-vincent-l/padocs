defmodule Textexp.Files.BunnyStorageTest do
  use ExUnit.Case, async: true

  alias Textexp.Files.BunnyStorage

  @opts [
    zone: "textexp-files",
    access_key: "zone-password",
    region: "DE",
    req_options: [plug: {Req.Test, __MODULE__}]
  ]

  test "put sends the bytes with the zone's password, to <hostname>/<zone>/<key>" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:request, conn.method, conn.host, conn.request_path, conn.req_headers, body})
      Plug.Conn.send_resp(conn, 201, ~s({"HttpCode":201}))
    end)

    assert :ok = BunnyStorage.put(@opts, "files/abc", "bytes", "image/png")

    assert_received {:request, "PUT", "storage.bunnycdn.com", "/textexp-files/files/abc", headers,
                     "bytes"}

    headers = Map.new(headers)
    assert headers["accesskey"] == "zone-password"
    assert headers["content-type"] == "application/octet-stream"
  end

  test "the hostname of the region, unless given" do
    assert BunnyStorage.hostname("DE") == "storage.bunnycdn.com"
    assert BunnyStorage.hostname(nil) == "storage.bunnycdn.com"
    assert BunnyStorage.hostname("UK") == "uk.storage.bunnycdn.com"

    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:host, conn.host})
      Plug.Conn.send_resp(conn, 201, "")
    end)

    :ok = BunnyStorage.put(Keyword.put(@opts, :region, "NY"), "k", "b", "image/png")
    assert_received {:host, "ny.storage.bunnycdn.com"}

    :ok = BunnyStorage.put(Keyword.put(@opts, :hostname, "se.storage.bunnycdn.com"), "k", "b", "")
    assert_received {:host, "se.storage.bunnycdn.com"}

    :ok = BunnyStorage.put(Keyword.put(@opts, :hostname, ""), "k", "b", "")
    assert_received {:host, "storage.bunnycdn.com"}
  end

  test "read gives the bytes as stored, a missing file :enoent" do
    Req.Test.stub(__MODULE__, fn conn ->
      case conn.request_path do
        "/textexp-files/files/abc" ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, ~s({"not": "decoded"}))

        _ ->
          Plug.Conn.send_resp(conn, 404, "")
      end
    end)

    assert {:ok, ~s({"not": "decoded"})} = BunnyStorage.read(@opts, "files/abc")
    assert {:error, :enoent} = BunnyStorage.read(@opts, "files/missing")
  end

  test "a wrong password is an error" do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 401, ""))
    assert {:error, {:http_status, 401}} = BunnyStorage.put(@opts, "files/abc", "b", "image/png")
  end

  test "deleting a missing file is not an error" do
    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:request, conn.method})
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = BunnyStorage.delete(@opts, "files/abc")
    assert_received {:request, "DELETE"}
  end

  test "the application sends the files itself" do
    assert BunnyStorage.serve(@opts, "files/abc") == :read
  end
end
