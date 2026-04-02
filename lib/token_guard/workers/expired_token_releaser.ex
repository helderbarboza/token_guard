defmodule TokenGuard.Workers.ExpiredTokenReleaser do
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job) do
    TokenGuard.Tokens.release_expired_tokens()
  end
end
