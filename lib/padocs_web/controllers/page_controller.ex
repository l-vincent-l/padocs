defmodule PadocsWeb.PageController do
  use PadocsWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/documents")
  end
end
