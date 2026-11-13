defmodule PadocsWeb.LocaleController do
  @moduledoc """
  Changes the language of the interface (see `PadocsWeb.Locale`): kept in the
  session, and on the account of a signed-in user, for their next sessions
  and their emails. Back to the page it was changed from.
  """
  use PadocsWeb, :controller

  alias Padocs.Accounts
  alias PadocsWeb.Locale

  def update(conn, %{"locale" => locale}) do
    if Locale.known?(locale) do
      if user = conn.assigns.current_user, do: {:ok, _} = Accounts.put_user_locale(user, locale)

      conn
      |> put_session("locale", locale)
      |> redirect(to: back(conn))
    else
      redirect(conn, to: back(conn))
    end
  end

  # The page of the Referer, on this site only.
  defp back(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: "/" <> _ = path} = uri <- URI.parse(referer),
         true <- host in [nil, conn.host] do
      if uri.query, do: path <> "?" <> uri.query, else: path
    else
      _ -> ~p"/documents"
    end
  end
end
