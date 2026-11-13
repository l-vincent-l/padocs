defmodule TextexpWeb.YDocRoomChannel do
  use TextexpWeb, :channel

  @doc_server_opts [
    endpoint: TextexpWeb.Endpoint,
    persistence: Textexp.Document.YPersistence,
    # the edits of each second are appended to the document's log
    flush_interval_ms: 1_000,
    presence: TextexpWeb.Presence,
    access: Textexp.Document.Access,
    supervisor: TextexpWeb.DocServerSupervisor,
    registry_scope: :doc_servers
  ]

  @doc "Options passed to `YPhoenix.Channel` and `YPhoenix.DocServer`."
  def doc_server_opts, do: @doc_server_opts

  # The document's DocServer gives the user's permission (see
  # Textexp.Document.Access): owner and editors edit, viewers join read-only.
  # A role changed while joined applies at once: an editor made viewer goes
  # read-only, a member removed leaves.
  @impl true
  def join("y_doc_room:" <> doc_name = topic, _payload, socket) do
    case socket.assigns.current_user do
      nil ->
        {:error, %{reason: "unauthorized"}}

      user ->
        YPhoenix.Channel.join(socket, topic, doc_name, user, doc_server_opts(doc_name))
    end
  end

  # Anyone, signed in or not, reads the document while `public_token` is its
  # public link's (see PublicDocumentLive), on a topic of its own: they get
  # the document's updates, not the awareness of its editors (their names),
  # and share none.
  def join("y_doc_public:" <> doc_name, %{"public_token" => token}, socket)
      when is_binary(token) do
    YPhoenix.Channel.join(
      socket,
      "y_doc_room:" <> doc_name,
      doc_name,
      {:public, token},
      [awareness: false] ++ doc_server_opts(doc_name)
    )
  end

  def join("y_doc_public:" <> _doc_name, _payload, _socket),
    do: {:error, %{reason: "unauthorized"}}

  defp doc_server_opts(doc_name),
    do: [updates_topic: "y_doc_public:" <> doc_name] ++ @doc_server_opts

  @impl true
  def handle_in(event, payload, socket), do: YPhoenix.Channel.handle_in(event, payload, socket)

  @impl true
  def handle_info(msg, socket), do: YPhoenix.Channel.handle_info(msg, socket)
end
