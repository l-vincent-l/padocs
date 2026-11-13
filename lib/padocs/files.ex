defmodule Padocs.Files do
  @moduledoc """
  The files of the documents: images, uploaded from the editor (into a
  document) or from a Word file being imported (without document until the
  import creates it, see `attach/3`).

  Their bytes are kept by the configured `Padocs.Files.Storage`, under
  `key/1`; a row of `Padocs.Files.StoredFile` says whose they are. Only
  PNG, JPEG, GIF and WebP images are taken, recognized by their first bytes
  whatever the browser says (no SVG, which could hold scripts), up to
  `max_bytes/0`.

  A file is read by whoever can read its document, or by anyone while the
  document has a public link (its id is only found in the document); a file
  without document, by its owner only. It is deleted with its document, for
  good (see `Padocs.Document.delete_document/1`): the history may still show
  it while the document exists.
  """
  import Ecto.Query

  require Logger

  alias Padocs.Document
  alias Padocs.Document.Policy
  alias Padocs.Files.StoredFile
  alias Padocs.SqliteRepo, as: Repo

  @max_bytes 10_000_000

  @doc "The largest file taken, in bytes."
  def max_bytes, do: @max_bytes

  @doc "The key of the file of `id` in the storage."
  def key(id), do: "files/#{id}"

  @doc "The path the browser gets the file of `id` at."
  def url(id), do: "/files/#{id}"

  @doc """
  Stores `data`, an image uploaded by `user`, in the document of
  `document_id`, which they must be able to write, or without document (`nil`)
  for an import. `{:ok, file}`, or `{:error, reason}`: `:forbidden`,
  `:unsupported_type`, `:too_large` or `:storage`.
  """
  def upload(user, document_id, data) when is_binary(data) do
    with :ok <- check_size(data),
         {:ok, content_type} <- image_type(data),
         :ok <- check_writable(user, document_id) do
      store(user, document_id, data, content_type)
    end
  end

  defp check_size(data) when byte_size(data) > @max_bytes, do: {:error, :too_large}
  defp check_size(data) when byte_size(data) == 0, do: {:error, :unsupported_type}
  defp check_size(_data), do: :ok

  defp check_writable(_user, nil), do: :ok

  defp check_writable(user, document_id) do
    case Document.get_document(document_id, user) do
      {:ok, document} ->
        if Policy.can?(document.role, :write), do: :ok, else: {:error, :forbidden}

      {:error, _} ->
        {:error, :forbidden}
    end
  end

  # The row first, then the bytes: a file listed is stored, or its row is
  # removed again.
  defp store(user, document_id, data, content_type) do
    file =
      Repo.insert!(%StoredFile{
        document_id: document_id,
        owner_id: user.id,
        content_type: content_type,
        size: byte_size(data)
      })

    {module, opts} = storage()

    case module.put(opts, key(file.id), data, content_type) do
      :ok ->
        {:ok, file}

      {:error, reason} ->
        Logger.error("File #{file.id} not stored: #{inspect(reason)}")
        Repo.delete!(file)
        {:error, :storage}
    end
  end

  @doc """
  The type of an image by its first bytes: `{:ok, content_type}`, or
  `{:error, :unsupported_type}`.
  """
  def image_type(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>), do: {:ok, "image/png"}
  def image_type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: {:ok, "image/jpeg"}
  def image_type(<<"GIF8", v, "a", _::binary>>) when v in [?7, ?9], do: {:ok, "image/gif"}
  def image_type(<<"RIFF", _size::32, "WEBP", _::binary>>), do: {:ok, "image/webp"}
  def image_type(_data), do: {:error, :unsupported_type}

  @doc """
  The file of `id`, if `user` (`nil` when not signed in) can read it:
  `{:ok, file}` or `{:error, :not_found}`.
  """
  def get_readable(id, user) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %StoredFile{} = file <- Repo.get(StoredFile, id),
         true <- readable?(file, user) do
      {:ok, file}
    else
      _ -> {:error, :not_found}
    end
  end

  defp readable?(%StoredFile{document_id: nil, owner_id: owner_id}, user),
    do: user != nil and user.id == owner_id

  defp readable?(%StoredFile{document_id: document_id}, user) do
    (user != nil and match?({:ok, _}, Document.get_document(document_id, user))) or
      Document.public_token(document_id) != nil
  end

  @doc "How to send `file` to a browser (see `c:Padocs.Files.Storage.serve/2`)."
  def serve(%StoredFile{id: id}) do
    {module, opts} = storage()
    module.serve(opts, key(id))
  end

  @doc "The bytes of `file`: `{:ok, data}` or `{:error, reason}`."
  def read(%StoredFile{id: id}) do
    {module, opts} = storage()
    module.read(opts, key(id))
  end

  @doc """
  Puts the files of `ids` that `user` uploaded without document, for an
  import, into the document of `document_id`; the others are left alone.
  """
  def attach(user, ids, document_id) when is_list(ids) do
    ids = for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], do: id

    Repo.update_all(
      from(f in StoredFile,
        where: f.id in ^ids and f.owner_id == ^user.id and is_nil(f.document_id)
      ),
      set: [document_id: document_id]
    )

    :ok
  end

  @doc "The ids of the files of the documents of `document_ids`."
  def list_ids(document_ids) do
    Repo.all(from f in StoredFile, where: f.document_id in ^document_ids, select: f.id)
  end

  @doc """
  Deletes the bytes of the files of `ids`, whose rows are gone with their
  documents. A failure is logged: the bytes stay, unreachable.
  """
  def delete_stored(ids) do
    {module, opts} = storage()

    for id <- ids do
      case module.delete(opts, key(id)) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("File #{id} not deleted: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp storage, do: Application.fetch_env!(:padocs, __MODULE__) |> Keyword.fetch!(:storage)
end
