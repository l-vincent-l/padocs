defmodule PadocsWeb.UserSocket do
  use Phoenix.Socket

  ## Channels

  channel "y_doc_room:*", PadocsWeb.YDocRoomChannel
  channel "y_doc_room_memory_save:*", PadocsWeb.YDocRoomChannel
  channel "y_doc_public:*", PadocsWeb.YDocRoomChannel

  # The signed-in user, from the session, or `nil` for anyone opening a
  # public link (see YDocRoomChannel).
  @impl true
  def connect(_params, socket, connect_info) do
    user = PadocsWeb.UserAuth.session_user(connect_info[:session] || %{})
    {:ok, assign(socket, :current_user, user)}
  end

  # A user's sockets are closed when they sign out (see UserAuth); the others
  # are anonymous.
  @impl true
  def id(%{assigns: %{current_user: nil}}), do: nil
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
