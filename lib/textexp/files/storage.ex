defmodule Textexp.Files.Storage do
  @moduledoc """
  Where the bytes of the files are kept (see `Textexp.Files`): a local folder
  (`Textexp.Files.LocalStorage`, the default), an S3 bucket
  (`Textexp.Files.S3Storage`) or a Bunny Storage zone
  (`Textexp.Files.BunnyStorage`), chosen by the `:textexp, Textexp.Files` config:

      config :textexp, Textexp.Files, storage: {Textexp.Files.LocalStorage, root: "/data/files"}

  Each takes its options as first argument.
  """

  @type opts :: keyword()

  @callback put(opts(), key :: String.t(), data :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}

  @callback read(opts(), key :: String.t()) :: {:ok, binary()} | {:error, term()}

  @callback delete(opts(), key :: String.t()) :: :ok | {:error, term()}

  @doc """
  How the file is sent to a browser: `{:path, path}`, a local file;
  `{:url, url}`, a URL valid for a few minutes, to redirect to; or `:read`,
  its bytes read with `c:read/2`, by the application.
  """
  @callback serve(opts(), key :: String.t()) :: {:path, Path.t()} | {:url, String.t()} | :read
end
