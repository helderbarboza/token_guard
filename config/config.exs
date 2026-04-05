# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :token_guard,
  ecto_repos: [TokenGuard.Repo],
  generators: [timestamp_type: :utc_datetime],
  token_lifetime: :timer.minutes(2)

# Configure the endpoint
config :token_guard, TokenGuardWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TokenGuardWeb.ErrorHTML, json: TokenGuardWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TokenGuard.PubSub,
  live_view: [signing_salt: "Ev7DIW88"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :user_id,
    :token_id,
    :reason,
    :released_count,
    :expired_count,
    :deadline,
    :errors,
    :token_count,
    :usage_count
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
