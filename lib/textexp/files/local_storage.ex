defmodule Textexp.Files.LocalStorage do
  @moduledoc """
  The files in a local folder, `:root`: on Fly.io, next to the database, on
  the volume. Each key is a path under it.
  """
  @behaviour Textexp.Files.Storage

  @impl true
  def put(opts, key, data, _content_type) do
    path = path(opts, key)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      # Written aside then renamed: a file is there whole or not at all.
      tmp = path <> ".tmp"

      with :ok <- File.write(tmp, data), do: File.rename(tmp, path)
    end
  end

  @impl true
  def read(opts, key), do: File.read(path(opts, key))

  @impl true
  def delete(opts, key) do
    case File.rm(path(opts, key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      error -> error
    end
  end

  @impl true
  def serve(opts, key), do: {:path, path(opts, key)}

  # The keys are made by Textexp.Files, of an id: never `..`.
  defp path(opts, key), do: Path.join(Keyword.fetch!(opts, :root), key)
end
