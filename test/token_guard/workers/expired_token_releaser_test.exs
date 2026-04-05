defmodule TokenGuard.Workers.ExpiredTokenReleaserTest do
  use TokenGuard.DataCase, async: false

  alias TokenGuard.Tokens
  alias TokenGuard.Workers.ExpiredTokenReleaser

  @valid_job %{queue: :default, worker: ExpiredTokenReleaser, args: %{}}

  describe "perform/1" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "returns :ok when no tokens are expired" do
      # Assert all tokens are available initially
      assert length(Tokens.list_available_tokens()) == 100
      assert Tokens.list_active_tokens() == []

      # Perform the worker job
      result = ExpiredTokenReleaser.perform(@valid_job)

      # Should return :ok with zero counts
      assert result == {:ok, %{token_count: 0, usage_count: 0}}

      # No tokens should have been released since none were active
      assert length(Tokens.list_available_tokens()) == 100
      assert Tokens.list_active_tokens() == []
    end

    test "releases tokens that have been active longer than token lifetime" do
      # Activate a token
      user_id = Ecto.UUID.generate()
      {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id

      # Verify token is active
      token = Tokens.get_token!(token_id)
      assert token.status == :active

      # Set the token's started_at time to be older than the token lifetime (2 minutes)
      # Using 121 seconds to ensure it's past the 2 minute threshold
      past = DateTime.add(DateTime.utc_now(:second), -121, :second)
      usage = Tokens.get_active_usage_for_token(token_id)
      assert usage != nil

      # Update the usage record to make it appear expired
      usage
      |> Ecto.Changeset.change(%{started_at: past})
      |> Repo.update!()

      # Perform the worker job
      result = ExpiredTokenReleaser.perform(@valid_job)

      # Should return :ok
      assert result == {:ok, %{token_count: 1, usage_count: 1}}

      # Token should now be available
      updated_token = Tokens.get_token!(token_id)
      assert updated_token.status == :available

      # Usage record should have ended_at set
      expired_usage = Tokens.get_active_usage_for_token(token_id)
      assert expired_usage == nil

      # Check that we have one less active token and one more available token
      assert Tokens.list_active_tokens() == []
      assert length(Tokens.list_available_tokens()) == 100
    end

    test "releases multiple expired tokens" do
      # Activate multiple tokens
      user_ids = for _i <- 1..3, do: Ecto.UUID.generate()

      activations =
        Enum.map(user_ids, fn user_id ->
          Tokens.activate_token(user_id)
        end)

      # Verify all tokens are active
      token_ids = Enum.map(activations, fn {:ok, activation} -> activation.token_id end)
      tokens = Enum.map(token_ids, fn id -> Tokens.get_token!(id) end)
      assert Enum.all?(tokens, &(&1.status == :active))

      # Make all tokens expire by setting their start time in the past
      past = DateTime.add(DateTime.utc_now(:second), -121, :second)

      Enum.each(activations, fn {:ok, activation} ->
        usage = Tokens.get_active_usage_for_token(activation.token_id)

        usage
        |> Ecto.Changeset.change(started_at: past)
        |> Repo.update!()
      end)

      # Perform the worker job
      result = ExpiredTokenReleaser.perform(@valid_job)

      # Should return :ok
      assert result == {:ok, %{token_count: 3, usage_count: 3}}

      # All tokens should now be available
      Enum.each(token_ids, fn token_id ->
        updated_token = Tokens.get_token!(token_id)
        assert updated_token.status == :available
      end)

      # Check that we have no active tokens and all tokens available
      assert Tokens.list_active_tokens() == []
      assert length(Tokens.list_available_tokens()) == 100
    end

    test "does not release tokens active for less than token lifetime" do
      # Activate a token
      user_id = Ecto.UUID.generate()
      {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id

      # Verify token is active
      token = Tokens.get_token!(token_id)
      assert token.status == :active

      # Set the token's started_at time to be within the token lifetime (less than 2 minutes ago)
      # Using 119 seconds to ensure it's under the 2 minute threshold
      recent = DateTime.add(DateTime.utc_now(:second), -119, :second)
      usage = Tokens.get_active_usage_for_token(token_id)
      assert usage != nil

      # Update the usage record to make it appear not expired
      usage
      |> Ecto.Changeset.change(%{started_at: recent})
      |> Repo.update!()

      # Perform the worker job
      result = ExpiredTokenReleaser.perform(@valid_job)

      # Should return :ok
      assert result == {:ok, %{token_count: 0, usage_count: 0}}

      # Token should still be active
      updated_token = Tokens.get_token!(token_id)
      assert updated_token.status == :active

      # Usage record should still have nil ended_at
      active_usage = Tokens.get_active_usage_for_token(token_id)
      assert active_usage != nil
      assert is_nil(active_usage.ended_at)

      # Check that we still have one active token
      assert length(Tokens.list_active_tokens()) == 1
      assert length(Tokens.list_available_tokens()) == 99
    end
  end
end
