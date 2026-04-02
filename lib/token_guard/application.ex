defmodule TokenGuard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TokenGuardWeb.Telemetry,
      TokenGuard.Repo,
      {DNSCluster, query: Application.get_env(:token_guard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TokenGuard.PubSub},
      TokenGuardWeb.Endpoint
    ]

    children =
      if Application.get_env(:token_guard, :start_oban, true) do
        oban_config = Application.get_env(:token_guard, Oban) || [repo: TokenGuard.Repo]
        children ++ [{Oban, oban_config}]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TokenGuard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TokenGuardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
