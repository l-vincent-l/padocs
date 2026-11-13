defmodule Padocs.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Syn scopes for distributed DocServer registry
    :syn.add_node_to_scopes([:doc_servers])

    children = [
      PadocsWeb.Telemetry,
      Padocs.SqliteRepo,
      {DNSCluster, query: Application.get_env(:padocs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Padocs.PubSub},
      PadocsWeb.Presence,
      # After the Repo and the PubSub: indexes all the documents, then those
      # changed, as told on the PubSub.
      {Padocs.Document.SearchIndex,
       Application.get_env(:padocs, Padocs.Document.SearchIndex, [])},
      # After the Repo, before the DocServers: on shutdown, it writes the
      # last updates they handed over, once they are stopped.
      Padocs.Document.UpdateWriter,
      # After the Repo: on shutdown, DocServers are stopped (and flushed)
      # before it.
      {DynamicSupervisor, name: PadocsWeb.DocServerSupervisor, strategy: :one_for_one},
      # Start a worker by calling: Padocs.Worker.start_link(arg)
      # {Padocs.Worker, arg},
      # Start to serve requests, typically the last entry
      PadocsWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Padocs.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PadocsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
