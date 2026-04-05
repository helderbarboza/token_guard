defmodule TokenGuard.Workers.ExpiredTokenReleaserTest do
  use TokenGuard.DataCase, async: false

  import Ecto.Query

  alias TokenGuard.Repo
  alias TokenGuard.Tokens
  alias TokenGuard.Workers.ExpiredTokenReleaser

  @token_lifetime_ms Application.compile_env(:token_guard, :token_lifetime, :timer.minutes(2))
  @expired_offset_seconds div(@token_lifetime_ms, 1000) + 10

  describe "perform/1" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "releases tokens that have been active for more than token lifetime" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(activation.token_id)

      assert token.status == :active

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenGuard.Tokens.TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      assert :ok = ExpiredTokenReleaser.perform(%Oban.Job{})

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == :available
    end

    test "does not release tokens active for less than token lifetime" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(activation.token_id)

      assert token.status == :active

      assert :ok = ExpiredTokenReleaser.perform(%Oban.Job{})

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == :active
    end

    test "releases multiple expired tokens" do
      {:ok, activation1} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, activation2} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, activation3} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      for act <- [activation1, activation2, activation3] do
        TokenGuard.Tokens.TokenUsage
        |> where(token_id: ^act.token_id)
        |> Repo.update_all(set: [started_at: expired_time])
      end

      assert :ok = ExpiredTokenReleaser.perform(%Oban.Job{})

      active_tokens = Tokens.list_active_tokens()
      assert active_tokens == []
    end
  end
end
