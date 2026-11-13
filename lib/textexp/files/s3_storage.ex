defmodule Textexp.Files.S3Storage do
  @moduledoc """
  The files in an S3 bucket, of any service speaking its API (AWS, Tigris on
  Fly.io, MinIO…), through Req and its AWS signature. Options:

    * `:bucket`, `:endpoint` (e.g. `https://fly.storage.tigris.dev`),
      `:region` (`"auto"` for Tigris), `:access_key_id`,
      `:secret_access_key`;
    * `:prefix` - put before each key, e.g. `"textexp/"` to share a bucket
      (default none);
    * `:req_options` - for the tests (`plug: {Req.Test, ...}`).

  The URLs are path-style, `<endpoint>/<bucket>/<key>`. The bucket stays
  private: a browser gets a file by a signed URL, valid 5 minutes.
  """
  @behaviour Textexp.Files.Storage

  @url_expires_s 300

  @impl true
  def put(opts, key, data, content_type) do
    opts
    |> request(:put, key, body: data, headers: [{"content-type", content_type}])
    |> result()
  end

  @impl true
  def read(opts, key) do
    case request(opts, :get, key) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      other -> result(other)
    end
  end

  @impl true
  def delete(opts, key) do
    case request(opts, :delete, key) do
      # deleting a missing key is not an error
      {:ok, %Req.Response{status: 404}} -> :ok
      other -> result(other)
    end
  end

  @impl true
  def serve(opts, key) do
    url =
      Req.Utils.aws_sigv4_url(
        method: :get,
        url: url(opts, key),
        service: :s3,
        region: Keyword.fetch!(opts, :region),
        access_key_id: Keyword.fetch!(opts, :access_key_id),
        secret_access_key: Keyword.fetch!(opts, :secret_access_key),
        datetime: DateTime.utc_now(),
        expires: @url_expires_s
      )

    {:url, to_string(url)}
  end

  defp request(opts, method, key, options \\ []) do
    [
      method: method,
      url: url(opts, key),
      aws_sigv4: [
        service: :s3,
        region: Keyword.fetch!(opts, :region),
        access_key_id: Keyword.fetch!(opts, :access_key_id),
        secret_access_key: Keyword.fetch!(opts, :secret_access_key)
      ],
      # the body as the bytes stored, whatever their type
      decode_body: false,
      retry: :transient
    ]
    |> Keyword.merge(options)
    |> Keyword.merge(Keyword.get(opts, :req_options, []))
    |> Req.request()
  end

  defp result({:ok, %Req.Response{status: status}}) when status in 200..299, do: :ok
  defp result({:ok, %Req.Response{status: status}}), do: {:error, {:http_status, status}}
  defp result({:error, reason}), do: {:error, reason}

  defp url(opts, key) do
    endpoint = opts |> Keyword.fetch!(:endpoint) |> String.trim_trailing("/")
    path = Keyword.get(opts, :prefix, "") <> key
    "#{endpoint}/#{Keyword.fetch!(opts, :bucket)}/#{path}"
  end
end
