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
    YPhoenix.Channel.join(socket, topic, doc_name, socket.assigns.current_user, @doc_server_opts)
  end

  @impl true
  def handle_in(event, payload, socket), do: YPhoenix.Channel.handle_in(event, payload, socket)

  @impl true
  def handle_info(msg, socket), do: YPhoenix.Channel.handle_info(msg, socket)
end
