defmodule TextexpWeb.FileControllerTest do
  use TextexpWeb.ConnCase

  alias Textexp.{Document, Files, Fixtures}

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "rest of the image">>

  setup %{conn: conn} do
    owner = Fixtures.confirmed_user()
    document = Fixtures.create_document!(owner, %{title: "Notes"})
    %{conn: Fixtures.log_in(conn, owner), owner: owner, document: document}
  end

  defp upload(conn, path, data) do
    conn
    |> put_req_header("content-type", "application/octet-stream")
    |> post(path, data)
  end

  test "an image uploaded into a document is read back", %{conn: conn, document: document} do
    conn = upload(conn, ~p"/documents/#{document.id}/files", @png)
    assert %{"id" => id, "url" => url} = json_response(conn, 201)
    assert url == "/files/#{id}"

    conn = get(recycle(conn), url)
    assert response(conn, 200) == @png
    assert response_content_type(conn, :png) =~ "image/png"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert ["private" <> _] = get_resp_header(conn, "cache-control")
  end

  test "an image of an import, without document", %{conn: conn, owner: owner} do
    conn = upload(conn, ~p"/files", @png)
    assert %{"id" => id} = json_response(conn, 201)
    assert {:ok, %{document_id: nil}} = Files.get_readable(id, owner)
  end

  test "not signed in, nothing is uploaded", %{document: document} do
    conn = upload(build_conn(), ~p"/documents/#{document.id}/files", @png)
    assert json_response(conn, 401)
  end

  test "a document the user cannot write", %{document: document} do
    conn =
      build_conn()
      |> Fixtures.log_in(Fixtures.confirmed_user())
      |> upload(~p"/documents/#{document.id}/files", @png)

    assert %{"error" => "forbidden"} = json_response(conn, 403)
  end

  test "not an image, or too large", %{conn: conn, document: document} do
    path = ~p"/documents/#{document.id}/files"

    assert %{"error" => "unsupported_type"} =
             conn |> upload(path, "<svg></svg>") |> json_response(415)

    big = @png <> :binary.copy("x", Files.max_bytes())

    assert %{"error" => "too_large"} =
             conn |> upload(path, big) |> json_response(413)
  end

  test "a file is not found by who cannot read its document", %{
    conn: conn,
    owner: owner,
    document: document
  } do
    {:ok, file} = Files.upload(owner, document.id, @png)

    stranger = build_conn() |> Fixtures.log_in(Fixtures.confirmed_user())
    assert stranger |> get(~p"/files/#{file.id}") |> response(404)
    assert build_conn() |> get(~p"/files/#{file.id}") |> response(404)
    assert conn |> get(~p"/files/#{Ecto.UUID.generate()}") |> response(404)
  end

  test "anyone reads it while the document has a public link", %{
    owner: owner,
    document: document
  } do
    {:ok, file} = Files.upload(owner, document.id, @png)
    {:ok, _token} = Document.enable_public_link(owner, document.id)

    assert build_conn() |> get(~p"/files/#{file.id}") |> response(200) == @png
  end

  describe "from a Bunny Storage zone" do
    setup do
      previous = Application.fetch_env!(:textexp, Files)

      Application.put_env(:textexp, Files,
        storage:
          {Textexp.Files.BunnyStorage,
           zone: "zone", access_key: "key", req_options: [plug: {Req.Test, __MODULE__}]}
      )

      on_exit(fn -> Application.put_env(:textexp, Files, previous) end)
    end

    test "the application reads and sends the bytes", %{conn: conn, document: document} do
      Req.Test.stub(__MODULE__, fn conn ->
        case conn.method do
          "PUT" -> Plug.Conn.send_resp(conn, 201, "")
          "GET" -> Plug.Conn.send_resp(conn, 200, @png)
        end
      end)

      conn = upload(conn, ~p"/documents/#{document.id}/files", @png)
      assert %{"url" => url} = json_response(conn, 201)

      conn = get(recycle(conn), url)
      assert response(conn, 200) == @png
      assert response_content_type(conn, :png) =~ "image/png"
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    end

    test "a zone that does not answer", %{conn: conn, owner: owner, document: document} do
      Req.Test.stub(__MODULE__, fn conn ->
        case conn.method do
          "PUT" -> Plug.Conn.send_resp(conn, 201, "")
          "GET" -> Plug.Conn.send_resp(conn, 403, "")
        end
      end)

      {:ok, file} = Files.upload(owner, document.id, @png)
      assert conn |> get(~p"/files/#{file.id}") |> response(503)
    end

    @tag :capture_log
    test "a file the zone refuses is not kept", %{conn: conn, document: document} do
      Req.Test.stub(__MODULE__, &Plug.Conn.send_resp(&1, 401, ""))

      conn = upload(conn, ~p"/documents/#{document.id}/files", @png)
      assert %{"error" => "storage"} = json_response(conn, 503)
      assert Files.list_ids([document.id]) == []
    end
  end
end
