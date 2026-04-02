defmodule TokenGuard.Workers.ExpiredTokenReleaser do
  @moduledoc """
  Oban worker that releases expired tokens.
  Runs every minute to check for tokens that have been active for more than 2 minutes.
  """
  use Oban.Worker, queue: :default
  require Logger

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("ExpiredTokenReleaser job started")
    TokenGuard.Tokens.release_expired_tokens()
    :ok
  end
end
