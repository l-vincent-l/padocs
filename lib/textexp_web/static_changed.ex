defmodule TextexpWeb.StaticChanged do
  @moduledoc """
  Reloads a page whose JavaScript or CSS is out of date: after a deploy, its
  LiveView reconnects to the new version, which tells, from the assets the
  page tracks (`phx-track-static` in the root layout), whether they changed
  (`Phoenix.LiveView.static_changed?/1`). It then pushes `static-changed`,
  on which app.js reloads the page.

  Nothing is lost: the edits of a document are kept in the browser
  (IndexedDB) and sent again once reloaded.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) and static_changed?(socket),
      do: {:cont, push_event(socket, "static-changed", %{})},
      else: {:cont, socket}
  end
end
