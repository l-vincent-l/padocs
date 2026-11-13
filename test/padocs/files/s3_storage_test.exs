defmodule Padocs.Files.S3StorageTest do
  use ExUnit.Case, async: true

  alias Padocs.Files.S3Storage

  @opts [
    bucket: "padocs-files",
    prefix: "prod/",
    endpoint: "https://s3.example.com/",
    region: "auto",
    access_key_id: "AKIDEXAMPLE",
    secret_access_key: "secret",
    req_options: [plug: {Req.Test, __MODULE__}]
  ]

  test "put sends the bytes, signed, to <endpoint>/<bucket>/<prefix><key>" do
    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(self(), {:request, conn.method, conn.request_path, conn.req_headers, body})
      Plug.Conn.send_resp(conn, 200, "")
    end)

    assert :ok = S3Storage.put(@opts, "files/abc", "bytes", "image/png")

    assert_received {:request, "PUT", "/padocs-files/prod/files/abc", headers, "bytes"}
    headers = Map.new(headers)
    assert headers["content-type"] == "image/png"
    assert "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/" <> _ = headers["authorization"]
    assert headers["authorization"] =~ "/auto/s3/aws4_request"
  end

  test "read gives the bytes as stored" do
    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"not": "decoded"}))
    end)

    assert {:ok, ~s({"not": "decoded"})} = S3Storage.read(@opts, "files/abc")
  end

  test "an error status is an error" do
    Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 403, "denied"))

    assert {:error, {:http_status, 403}} = S3Storage.put(@opts, "files/abc", "bytes", "image/png")
    assert {:error, {:http_status, 403}} = S3Storage.read(@opts, "files/abc")
  end

  test "deleting a missing file is not an error" do
    Req.Test.stub(__MODULE__, fn conn ->
      send(self(), {:request, conn.method})
      Plug.Conn.send_resp(conn, 404, "")
    end)

    assert :ok = S3Storage.delete(@opts, "files/abc")
    assert_received {:request, "DELETE"}
  end

  test "serve gives a signed URL valid 5 minutes" do
    assert {:url, url} = S3Storage.serve(@opts, "files/abc")

    uri = URI.parse(url)
    assert uri.host == "s3.example.com"
    assert uri.path == "/padocs-files/prod/files/abc"

    query = URI.decode_query(uri.query)
    assert query["X-Amz-Expires"] == "300"
    assert query["X-Amz-Signature"] =~ ~r/^[0-9a-f]{64}$/
  end
end
