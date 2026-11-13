defmodule Textexp.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialize Syn scopes for distributed DocServer registry
    :syn.add_node_to_scopes([:doc_servers])

    children = [
      TextexpWeb.Telemetry,
      Textexp.SqliteRepo,
      {DNSCluster, query: Application.get_env(:textexp, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Textexp.PubSub},
      TextexpWeb.Presence,
      # After the Repo, before the DocServers: on shutdown, it writes the
      # last updates they handed over, once they are stopped.
      Textexp.Document.UpdateWriter,
      # After the Repo: on shutdown, DocServers are stopped (and flushed)
      # before it.
      {DynamicSupervisor, name: TextexpWeb.DocServerSupervisor, strategy: :one_for_one},
      # Start a worker by calling: Textexp.Worker.start_link(arg)
      # {Textexp.Worker, arg},
      # Start to serve requests, typically the last entry
      TextexpWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Textexp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TextexpWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
