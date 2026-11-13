defmodule PadocsWeb.FileController do
  @moduledoc """
  The files of the documents (see `Padocs.Files`):

    * `POST /documents/:id/files` - an image pasted or dropped in the editor
      of a document the user can write (BlockNote's `uploadFile`);
    * `POST /files` - an image of a Word file being imported, before its
      document exists (see `Padocs.Document.import_document/4`);
    * `GET /files/:id` - a file, to whoever can read it: sent from the local
      folder or read from a Bunny Storage zone, or by a redirect to a signed
      URL of the S3 bucket.

  An upload is the raw bytes of the file as the request's body (the browser's
  `fetch(url, {method: "POST", body: file})`), with the CSRF token in the
  `x-csrf-token` header; the reply is `{"id", "url"}`.
  """
  use PadocsWeb, :controller

  alias Padocs.Files

  def create(%{assigns: %{current_user: nil}} = conn, _params),
    do: conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})

  def create(conn, params) do
    with {:ok, data, conn} <- read_file(conn),
         {:ok, file} <- Files.upload(conn.assigns.current_user, params["id"], data) do
      conn |> put_status(:created) |> json(%{id: file.id, url: Files.url(file.id)})
    else
      {:error, reason, conn} -> error(conn, reason)
      {:error, reason} -> error(conn, reason)
    end
  end

  # The body, at most one byte more than a file may have, to tell it is too
  # large.
  defp read_file(conn) do
    case read_body(conn, length: Files.max_bytes() + 1, read_length: 1_000_000) do
      {:ok, data, conn} -> {:ok, data, conn}
      {:more, _partial, conn} -> {:error, :too_large, conn}
      {:error, _reason} -> {:error, :unreadable, conn}
    end
  end

  defp error(conn, reason) do
    status =
      case reason do
        :forbidden -> :forbidden
        :too_large -> :request_entity_too_large
        :unsupported_type -> :unsupported_media_type
        :storage -> :service_unavailable
        _ -> :bad_request
      end

    conn |> put_status(status) |> json(%{error: to_string(reason)})
  end

  def show(conn, %{"id" => id}) do
    case Files.get_readable(id, conn.assigns.current_user) do
      {:ok, file} -> send_stored(conn, file)
      {:error, :not_found} -> conn |> put_status(:not_found) |> text("Fichier introuvable")
    end
  end

  # A file's bytes never change: it is cached, but only by the browser, as
  # its access may be withdrawn. Shown as an image, never run as a page.
  defp send_stored(conn, file) do
    case Files.serve(file) do
      {:path, path} ->
        conn |> put_image_headers(file) |> send_file(200, path)

      :read ->
        case Files.read(file) do
          {:ok, data} ->
            conn |> put_image_headers(file) |> send_resp(200, data)

          {:error, _reason} ->
            conn |> put_status(:service_unavailable) |> text("Fichier indisponible")
        end

      {:url, url} ->
        conn
        # shorter than the signed URL's validity
        |> put_resp_header("cache-control", "private, max-age=240")
        |> redirect(external: url)
    end
  end

  defp put_image_headers(conn, file) do
    conn
    |> put_resp_content_type(file.content_type, nil)
    |> put_resp_header("cache-control", "private, max-age=86400")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
  end
end
