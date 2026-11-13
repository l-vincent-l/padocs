defmodule PadocsWeb.UserSocketTest do
  use Padocs.DataCase

  alias Padocs.Fixtures

  import Phoenix.ChannelTest

  @endpoint PadocsWeb.Endpoint

  alias PadocsWeb.UserSocket

  defp register_user, do: Fixtures.register_user()

  defp session_for(user),
    do: %{"user_token" => Padocs.Accounts.generate_user_session_token(user)}

  # Anyone opening a public link connects; the channel checks the token.
  test "accepts a connection without a signed-in user, anonymous" do
    assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{session: %{}})
    assert socket.assigns.current_user == nil
    assert UserSocket.id(socket) == nil
  end

  test "an unknown session token connects anonymously" do
    session = %{"user_token" => "not-a-valid-token"}
    assert {:ok, socket} = connect(UserSocket, %{}, connect_info: %{session: session})
    assert socket.assigns.current_user == nil
  end

  test "accepts a signed-in user and identifies the socket by user" do
    user = register_user()

    assert {:ok, socket} =
             connect(UserSocket, %{}, connect_info: %{session: session_for(user)})

    assert socket.assigns.current_user.id == user.id
    assert UserSocket.id(socket) == "user_socket:#{user.id}"
  end
end
