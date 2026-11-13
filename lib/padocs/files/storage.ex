defmodule Padocs.Files.Storage do
  @moduledoc """
  Where the bytes of the files are kept (see `Padocs.Files`): a local folder
  (`Padocs.Files.LocalStorage`, the default), an S3 bucket
  (`Padocs.Files.S3Storage`) or a Bunny Storage zone
  (`Padocs.Files.BunnyStorage`), chosen by the `:padocs, Padocs.Files` config:

      config :padocs, Padocs.Files, storage: {Padocs.Files.LocalStorage, root: "/data/files"}

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
