defmodule Padocs.Files.BunnyStorage do
  @moduledoc """
  The files in a Bunny Storage zone, through its own HTTP API (not S3):
  `<hostname>/<zone>/<key>`, the zone's password in the `AccessKey` header.
  Options, from the variables Bunny gives a container linked to a zone
  (see config/runtime.exs):

    * `:zone` (`STORAGE_ZONE`), `:access_key` (`STORAGE_ACCESS_KEY`);
    * `:hostname` (`STORAGE_HOSTNAME`), or else the one of `:region`
      (`STORAGE_REGION`, e.g. `DE`, the main one, or `UK`, `NY`…);
    * `:req_options` - for the tests (`plug: {Req.Test, ...}`).

  The API has no signed URLs: the zone stays private and the application
  sends the bytes itself.
  """
  @behaviour Padocs.Files.Storage

  @impl true
  def put(opts, key, data, _content_type) do
    opts
    |> request(:put, key, body: data, headers: [{"content-type", "application/octet-stream"}])
    |> result()
  end

  @impl true
  def read(opts, key) do
    case request(opts, :get, key) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: 404}} -> {:error, :enoent}
      other -> result(other)
    end
  end

  @impl true
  def delete(opts, key) do
    case request(opts, :delete, key) do
      # deleting a missing file is not an error
      {:ok, %Req.Response{status: 404}} -> :ok
      other -> result(other)
    end
  end

  @impl true
  def serve(_opts, _key), do: :read

  @doc """
  The hostname of the storage API in `region`: `storage.bunnycdn.com` for the
  main one, Falkenstein (`DE`), `<region>.storage.bunnycdn.com` for the others.
  """
  def hostname(region) when region in [nil, "", "DE", "de"], do: "storage.bunnycdn.com"
  def hostname(region), do: "#{String.downcase(region)}.storage.bunnycdn.com"

  defp request(opts, method, key, options \\ []) do
    [
      method: method,
      url: url(opts, key),
      headers: [{"accesskey", Keyword.fetch!(opts, :access_key)}],
      # the body as the bytes stored, whatever their type
      decode_body: false,
      retry: :transient
    ]
    |> Keyword.merge(options, fn
      :headers, ours, theirs -> ours ++ theirs
      _key, _ours, theirs -> theirs
    end)
    |> Keyword.merge(Keyword.get(opts, :req_options, []))
    |> Req.request()
  end

  defp result({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok
  defp result({:ok, %Req.Response{status: status}}), do: {:error, {:http_status, status}}
  defp result({:error, reason}), do: {:error, reason}

  defp url(opts, key) do
    hostname =
      case Keyword.get(opts, :hostname) do
        host when host in [nil, ""] -> hostname(Keyword.get(opts, :region))
        host -> host
      end

    "https://#{hostname}/#{Keyword.fetch!(opts, :zone)}/#{key}"
  end
end
