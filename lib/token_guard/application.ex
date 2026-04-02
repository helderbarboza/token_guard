defmodule TokenGuard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    oban_config = Application.get_env(:token_guard, Oban, repo: TokenGuard.Repo)

    children = [
      TokenGuardWeb.Telemetry,
      TokenGuard.Repo,
      {Phoenix.PubSub, name: TokenGuard.PubSub},
      {Oban, oban_config},
      TokenGuardWeb.Endpoint
    ]

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
