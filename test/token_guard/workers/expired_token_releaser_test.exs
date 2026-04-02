defmodule TokenGuard.Workers.ExpiredTokenReleaserTest do
  use TokenGuard.DataCase, async: false

  import Ecto.Query

  alias TokenGuard.Tokens
  alias TokenGuard.Workers.ExpiredTokenReleaser

  describe "perform/1" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "releases tokens that have been active for more than 2 minutes" do
      {:ok, activation} = Tokens.activate_token()
      token = Tokens.get_token!(activation.token_id)

      assert token.status == "active"

      yesterday = DateTime.add(DateTime.utc_now(:second), -130, :second)

      TokenGuard.Tokens.TokenUsage
      |> where(token_id: ^activation.token_id)
      |> TokenGuard.Repo.update_all(set: [started_at: yesterday])

      assert :ok = ExpiredTokenReleaser.perform(%Oban.Job{})

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == "available"
    end

    test "does not release tokens active for less than 2 minutes" do
      {:ok, activation} = Tokens.activate_token()
      token = Tokens.get_token!(activation.token_id)

      assert token.status == "active"

      assert :ok = ExpiredTokenReleaser.perform(%Oban.Job{})

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == "active"
    end

    test "releases multiple expired tokens" do
      {:ok, activation1} = Tokens.activate_token()
      {:ok, activation2} = Tokens.activate_token()
      {:ok, activation3} = Tokens.activate_token()

      yesterday = DateTime.add(DateTime.utc_now(:second), -130, :second)

      for act <- [activation1, activation2, activation3] do
        TokenGuard.Tokens.TokenUsage
        |> where(token_id: ^act.token_id)
        |> TokenGuard.Repo.update_all(set: [started_at: yesterday])
      end

      assert :ok = ExpiredTokenReleaser.perform(%Oban.Job{})

      active_tokens = Tokens.list_active_tokens()
      assert active_tokens == []
    end
  end
end
