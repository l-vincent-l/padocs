defmodule PadocsWeb.ExportController do
  @moduledoc """
  Downloads a document the signed-in user can read, made on the server from
  its saved snapshot (the last seconds of edits may be missing, see
  `Padocs.Document.YPersistence`): as a PDF (compiled with Typst), Markdown,
  or the Typst source. Word and OpenDocument files are made in the browser,
  from the editor (see export.ts).
  """
  use PadocsWeb, :controller

  alias Padocs.Document

  @formats %{
    "pdf" => "application/pdf",
    "md" => "text/markdown",
    "typ" => "text/plain"
  }

  def show(%{assigns: %{current_user: nil}} = conn, _params),
    do: redirect(conn, to: ~p"/sign-in")

  def show(conn, %{"id" => id, "format" => format}) when is_map_key(@formats, format) do
    with {:ok, _readable} <- Document.get_document(id, conn.assigns.current_user),
         document = Document.get_document!(id),
         {:ok, content} <- content(document, format) do
      send_download(conn, {:binary, content},
        filename: "#{Document.export_filename(document)}.#{format}",
        content_type: @formats[format]
      )
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text(gettext("Document not found"))

      {:error, _reason} ->
        conn |> put_status(:internal_server_error) |> text(gettext("The export failed"))
    end
  end

  def show(conn, _params), do: conn |> put_status(:not_found) |> text(gettext("Unknown format"))

  # In the language of the interface (see PadocsWeb.Locale)
  defp content(document, "pdf"), do: Document.pdf(document, locale())
  defp content(document, "md"), do: {:ok, Document.markdown(document)}
  defp content(document, "typ"), do: {:ok, Document.typst(document, locale())}

  defp locale, do: Gettext.get_locale(PadocsWeb.Gettext)
end
