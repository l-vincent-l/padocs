defmodule TextexpWeb.YDocRoomChannelTest do
  use Textexp.DataCase

  alias Textexp.Fixtures

  import Phoenix.ChannelTest

  alias Textexp.Document
  alias TextexpWeb.{UserSocket, YDocRoomChannel}

  @endpoint TextexpWeb.Endpoint

  defp register_user, do: Fixtures.confirmed_user()

  defp join_as(user, document_id) do
    UserSocket
    |> socket("user_socket:#{user.id}", %{current_user: user})
    |> subscribe_and_join(YDocRoomChannel, "y_doc_room:#{document_id}")
  end

  # An edit of the text "t", as a Yjs client sends it.
  defp push_edit(socket, content) do
    source = Yex.Doc.new()
    source |> Yex.Doc.get_text("t") |> Yex.Text.insert(0, content)
    update = Yex.encode_state_as_update!(source)

    push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:sync, {:sync_update, update}})})
    # the channel has handed the message to the DocServer
    _ = :sys.get_state(socket.channel_pid)
  end

  # Leaves the channel (which would start the DocServer again), then stops the
  # DocServer, which saves the document if it was edited, and gives the saved
  # text.
  defp saved_text(socket, document) do
    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    close(socket)
    assert_receive {:DOWN, ^ref, :process, _pid, _reason}

    GenServer.stop(socket.assigns.doc_pid)

    case Document.get_document!(document.id).snapshot do
      nil ->
        nil

      snapshot ->
        doc = Yex.Doc.new()
        Yex.apply_update(doc, snapshot)
        doc |> Yex.Doc.get_text("t") |> Yex.Text.to_string()
    end
  end

  setup do
    owner = register_user()
    # Titled, so that it is kept, not deleted, when its DocServer stops.
    %{owner: owner, document: Fixtures.create_document!(owner, %{title: "Notes"})}
  end

  test "joining an unknown document is refused", %{owner: owner} do
    assert {:error, %{reason: "unauthorized"}} = join_as(owner, Ecto.UUID.generate())
  end

  test "joining another user's document is refused", %{document: document} do
    assert {:error, %{reason: "unauthorized"}} = join_as(register_user(), document.id)
  end

  test "the owner edits the document", %{owner: owner, document: document} do
    {:ok, _reply, socket} = join_as(owner, document.id)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == "hello"
  end

  test "an editor edits the document", %{owner: owner, document: document} do
    editor = register_user()
    Fixtures.share!(owner, document, editor, :editor)

    {:ok, _reply, socket} = join_as(editor, document.id)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == "hello"
  end

  # A Yjs client renews its unchanged awareness every 15 s, and the others
  # forget it if it is not renewed within 30 s.
  test "awareness renewals are relayed", %{owner: owner, document: document} do
    {:ok, _reply, socket} = join_as(owner, document.id)
    {:ok, client} = Yex.Awareness.new(Yex.Doc.new())

    for _renewal <- 1..2 do
      Yex.Awareness.set_local_state(client, %{"user" => "owner"})
      {:ok, update} = Yex.Awareness.encode_update(client, [Yex.Awareness.client_id(client)])
      push(socket, "yjs", {:binary, Yex.Sync.message_encode!({:awareness, update})})

      assert_broadcast "yjs", {:binary, <<1, _::binary>>}, 500
    end
  end

  test "a viewer joins, but its edits are dropped", %{owner: owner, document: document} do
    viewer = register_user()
    Fixtures.share!(owner, document, viewer, :viewer)

    {:ok, _reply, socket} = join_as(viewer, document.id)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == nil
  end

  # The DocServer has handled the change broadcast, and the channel the
  # permission it was then sent.
  defp sync(socket) do
    _ = :sys.get_state(socket.assigns.doc_pid)
    _ = :sys.get_state(socket.channel_pid)
  end

  test "an editor made viewer goes read-only at once", %{owner: owner, document: document} do
    member = register_user()
    Fixtures.share!(owner, document, member, :editor)
    {:ok, _reply, socket} = join_as(member, document.id)

    Fixtures.share!(owner, document, member, :viewer)
    sync(socket)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == nil
  end

  describe "public link" do
    defp join_public(token, document_id, user \\ nil) do
      UserSocket
      |> socket(nil, %{current_user: user})
      |> subscribe_and_join(YDocRoomChannel, "y_doc_public:#{document_id}", %{
        "public_token" => token
      })
    end

    defp awareness_message(name) do
      {:ok, client} = Yex.Awareness.new(Yex.Doc.new())
      Yex.Awareness.set_local_state(client, %{"user" => name})
      {:ok, update} = Yex.Awareness.encode_update(client, [Yex.Awareness.client_id(client)])
      {:binary, Yex.Sync.message_encode!({:awareness, update})}
    end

    test "without a user, the document's own topic is refused", %{
      owner: owner,
      document: document
    } do
      {:ok, token} = Document.enable_public_link(owner, document.id)

      for payload <- [%{}, %{"public_token" => token}] do
        assert {:error, %{reason: "unauthorized"}} =
                 UserSocket
                 |> socket(nil, %{current_user: nil})
                 |> subscribe_and_join(YDocRoomChannel, "y_doc_room:#{document.id}", payload)
      end
    end

    test "the public topic needs a token", %{document: document} do
      assert {:error, %{reason: "unauthorized"}} =
               UserSocket
               |> socket(nil, %{current_user: nil})
               |> subscribe_and_join(YDocRoomChannel, "y_doc_public:#{document.id}")
    end

    test "a reader gets the edits, not the editors' awareness", %{
      owner: owner,
      document: document
    } do
      {:ok, token} = Document.enable_public_link(owner, document.id)
      {:ok, _reply, reader} = join_public(token, document.id)

      # the owner joins with a socket of their own, not subscribed by the test
      {:ok, _reply, editor} =
        UserSocket
        |> socket("user_socket:#{owner.id}", %{current_user: owner})
        |> Phoenix.ChannelTest.join(YDocRoomChannel, "y_doc_room:#{document.id}")

      push(editor, "yjs", awareness_message(owner.email))
      _ = :sys.get_state(editor.assigns.doc_pid)
      push_edit(editor, "hello")
      _ = :sys.get_state(editor.assigns.doc_pid)

      # the edit, a sync message, comes through the public topic
      assert_push "yjs", {:binary, <<0, 2, _::binary>>}, 500
      refute_push "yjs", {:binary, <<1, _::binary>>}, 200

      # a query of the awareness gets nothing either
      push(reader, "yjs", {:binary, <<3>>})
      _ = :sys.get_state(reader.channel_pid)
      refute_push "yjs", {:binary, <<1, _::binary>>}, 200
    end

    test "a reader's awareness is not shared", %{owner: owner, document: document} do
      {:ok, token} = Document.enable_public_link(owner, document.id)
      {:ok, _reply, _editor} = join_as(owner, document.id)
      {:ok, _reply, reader} = join_public(token, document.id)

      push(reader, "yjs", awareness_message("Lecteur anonyme"))
      _ = :sys.get_state(reader.channel_pid)
      _ = :sys.get_state(reader.assigns.doc_pid)

      refute_broadcast "yjs", {:binary, <<1, _::binary>>}, 200
    end

    test "anyone joins with the token, read-only", %{owner: owner, document: document} do
      {:ok, token} = Document.enable_public_link(owner, document.id)

      {:ok, _reply, socket} = join_public(token, document.id)
      push_edit(socket, "hello")

      assert saved_text(socket, document) == nil
    end

    test "a signed-in user with the token reads too", %{owner: owner, document: document} do
      {:ok, token} = Document.enable_public_link(owner, document.id)
      assert {:ok, _reply, _socket} = join_public(token, document.id, register_user())
    end

    test "a wrong or replaced token is refused", %{owner: owner, document: document} do
      assert {:error, %{reason: "unauthorized"}} = join_public("nope", document.id)

      {:ok, old} = Document.enable_public_link(owner, document.id)
      {:ok, _new} = Document.enable_public_link(owner, document.id)
      assert {:error, %{reason: "unauthorized"}} = join_public(old, document.id)
    end

    test "the token of another document is refused", %{owner: owner, document: document} do
      other = Fixtures.create_document!(owner, %{title: "Autre"})
      {:ok, token} = Document.enable_public_link(owner, other.id)

      assert {:error, %{reason: "unauthorized"}} = join_public(token, document.id)
    end

    test "a link removed sends its readers away at once", %{owner: owner, document: document} do
      {:ok, token} = Document.enable_public_link(owner, document.id)
      {:ok, _reply, socket} = join_public(token, document.id)
      Process.unlink(socket.channel_pid)
      ref = Process.monitor(socket.channel_pid)

      :ok = Document.disable_public_link(owner, document.id)

      assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :unauthorized}}
    end

    test "a document put in the trash sends its readers away", %{
      owner: owner,
      document: document
    } do
      {:ok, token} = Document.enable_public_link(owner, document.id)
      {:ok, _reply, socket} = join_public(token, document.id)
      Process.unlink(socket.channel_pid)
      ref = Process.monitor(socket.channel_pid)

      :ok = Document.trash_document(document.id, owner)

      assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :unauthorized}}
    end
  end

  test "a member removed leaves the channel at once", %{owner: owner, document: document} do
    member = register_user()
    membership = Fixtures.share!(owner, document, member, :editor)
    {:ok, _reply, socket} = join_as(member, document.id)
    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)

    :ok = Document.remove_member(owner, membership.id)

    assert_receive {:DOWN, ^ref, :process, _pid, {:shutdown, :unauthorized}}
  end

  test "another member's change leaves the channel as it was",
       %{owner: owner, document: document} do
    editor = register_user()
    Fixtures.share!(owner, document, editor, :editor)
    {:ok, _reply, socket} = join_as(editor, document.id)

    Fixtures.share!(owner, document, register_user(), :viewer)
    sync(socket)
    push_edit(socket, "hello")

    assert saved_text(socket, document) == "hello"
  end
end
