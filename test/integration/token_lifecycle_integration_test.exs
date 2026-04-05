defmodule TokenGuard.Integration.TokenLifecycleIntegrationTest do
  @moduledoc """
  Integration test for the complete token lifecycle with Oban cron integration.

  The test uses Oban's inline testing mode to ensure cron jobs are executed
  synchronously in tests.
  """
  use TokenGuard.DataCase, async: false

  import Ecto.Query

  alias TokenGuard.Repo
  alias TokenGuard.Tokens
  alias TokenGuard.Tokens.TokenUsage
  alias TokenGuard.Workers.ExpiredTokenReleaser

  @token_lifetime_ms Application.compile_env(:token_guard, :token_lifetime, :timer.minutes(2))
  @token_lifetime_seconds div(@token_lifetime_ms, 1000)

  describe "full token lifecycle integration" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "register → active → auto-expire via Oban → released" do
      user_id = Ecto.UUID.generate()

      # Step 1: Register/activate token
      assert {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id
      registered_user_id = activation.user_id

      # Verify token is active and has usage record
      token = Tokens.get_token!(token_id)
      assert token.status == :active

      usage = Tokens.get_active_usage_for_token(token_id)
      assert usage != nil
      assert usage.user_id == registered_user_id
      assert usage.started_at != nil
      assert usage.ended_at == nil

      # Verify user can access their active token
      assert Tokens.get_active_usage_for_user(user_id) != nil

      # Step 2: Simulate waiting (token remains active)
      # Verify it's still active before expiration time
      assert token.status == :active
      assert length(Tokens.list_active_tokens()) == 1

      # Step 3: Simulate time passage - make token expired
      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      TokenUsage
      |> where(token_id: ^token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      # Verify token is still marked as active (not auto-released yet)
      token_before_job = Tokens.get_token!(token_id)
      assert token_before_job.status == :active

      # Step 4: Run the Oban worker job (simulates cron execution)
      # In test mode with Oban.Testing inline, jobs are executed synchronously
      assert {:ok, _result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      # Step 5: Verify released
      # Token should now be available
      token_after_job = Tokens.get_token!(token_id)
      assert token_after_job.status == :available

      # Usage record should have ended_at set
      usage_after =
        TokenUsage
        |> where(token_id: ^token_id)
        |> where([u], is_nil(u.ended_at) == false)
        |> Repo.one()

      assert usage_after != nil
      assert usage_after.ended_at != nil

      # User should no longer have active token
      assert Tokens.get_active_usage_for_user(user_id) == nil

      # Token should be in available list
      available_tokens = Tokens.list_available_tokens()
      assert Enum.any?(available_tokens, fn t -> t.id == token_id end)

      # Active tokens list should be empty
      assert Tokens.list_active_tokens() == []
    end

    test "multiple users' tokens expire and are released in single Oban job" do
      user_id_1 = Ecto.UUID.generate()
      user_id_2 = Ecto.UUID.generate()
      user_id_3 = Ecto.UUID.generate()

      # Step 1: Activate tokens for three users
      {:ok, activation_1} = Tokens.activate_token(user_id_1)
      {:ok, activation_2} = Tokens.activate_token(user_id_2)
      {:ok, activation_3} = Tokens.activate_token(user_id_3)

      token_id_1 = activation_1.token_id
      token_id_2 = activation_2.token_id
      token_id_3 = activation_3.token_id

      assert length(Tokens.list_active_tokens()) == 3

      # Step 2: Make all three tokens expired
      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      for token_id <- [token_id_1, token_id_2, token_id_3] do
        TokenUsage
        |> where(token_id: ^token_id)
        |> Repo.update_all(set: [started_at: expired_time])
      end

      # Step 3: Run Oban job
      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 3
      assert result.usage_count == 3

      # Step 4: Verify all tokens released
      for token_id <- [token_id_1, token_id_2, token_id_3] do
        token = Tokens.get_token!(token_id)
        assert token.status == :available
      end

      # All users should have no active tokens
      assert Tokens.get_active_usage_for_user(user_id_1) == nil
      assert Tokens.get_active_usage_for_user(user_id_2) == nil
      assert Tokens.get_active_usage_for_user(user_id_3) == nil

      # No active tokens should remain
      assert Tokens.list_active_tokens() == []

      # All three should be available
      available_tokens = Tokens.list_available_tokens()
      assert length(available_tokens) == 100
    end

    test "mixed scenario: some tokens expired, some still active" do
      user_id_1 = Ecto.UUID.generate()
      user_id_2 = Ecto.UUID.generate()
      user_id_3 = Ecto.UUID.generate()

      # Activate three tokens
      {:ok, activation_1} = Tokens.activate_token(user_id_1)
      {:ok, activation_2} = Tokens.activate_token(user_id_2)
      {:ok, activation_3} = Tokens.activate_token(user_id_3)

      token_id_1 = activation_1.token_id
      token_id_2 = activation_2.token_id
      token_id_3 = activation_3.token_id

      # Make only first two tokens expired
      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      for token_id <- [token_id_1, token_id_2] do
        TokenUsage
        |> where(token_id: ^token_id)
        |> Repo.update_all(set: [started_at: expired_time])
      end

      # Third token remains fresh (not modified, uses current time)

      # Run Oban job
      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 2
      assert result.usage_count == 2

      # First two should be released
      assert Tokens.get_token!(token_id_1).status == :available
      assert Tokens.get_token!(token_id_2).status == :available

      # Third should still be active
      assert Tokens.get_token!(token_id_3).status == :active

      # Check active tokens
      active_tokens = Tokens.list_active_tokens()
      assert length(active_tokens) == 1
      assert Enum.at(active_tokens, 0).id == token_id_3

      # Check active usage
      assert Tokens.get_active_usage_for_user(user_id_1) == nil
      assert Tokens.get_active_usage_for_user(user_id_2) == nil
      assert Tokens.get_active_usage_for_user(user_id_3) != nil
    end

    test "token history is preserved after expiration and release" do
      user_id = Ecto.UUID.generate()

      # Activate token
      {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id

      # Simulate expiration
      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      TokenUsage
      |> where(token_id: ^token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      # Run job to expire and release
      {:ok, _result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      # Verify history is preserved
      history = Tokens.get_token_history(token_id)
      assert length(history) == 1

      usage_record = Enum.at(history, 0)
      assert usage_record.user_id == user_id
      assert usage_record.token_id == token_id
      assert usage_record.started_at == expired_time
      assert usage_record.ended_at != nil
    end

    test "released token can be reused by new user" do
      user_id_1 = Ecto.UUID.generate()
      user_id_2 = Ecto.UUID.generate()

      # Step 1: User 1 activates token
      {:ok, activation_1} = Tokens.activate_token(user_id_1)
      token_id_1 = activation_1.token_id

      token = Tokens.get_token!(token_id_1)
      assert token.status == :active

      # Step 2: Make token expired
      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      TokenUsage
      |> where(token_id: ^token_id_1)
      |> Repo.update_all(set: [started_at: expired_time])

      # Step 3: Release via Oban job
      {:ok, _result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      # Step 4: Verify released
      token = Tokens.get_token!(token_id_1)
      assert token.status == :available

      # Step 5: User 2 activates - gets a token (released token is now available)
      {:ok, activation_2} = Tokens.activate_token(user_id_2)
      token_id_2 = activation_2.token_id

      # Token should be active
      token_2 = Tokens.get_token!(token_id_2)
      assert token_2.status == :active

      # Verify that both users now have active tokens
      assert Tokens.get_active_usage_for_user(user_id_1) == nil
      assert Tokens.get_active_usage_for_user(user_id_2) != nil

      # Verify token 1 shows both users in history if it was reused
      history = Tokens.get_token_history(token_id_1)

      if token_id_2 == token_id_1 do
        # Token was reused, should have both users in history
        assert length(history) == 2
        user_ids = Enum.map(history, fn u -> u.user_id end)
        assert user_id_1 in user_ids
        assert user_id_2 in user_ids
      else
        # Different tokens allocated, both should be active
        assert Tokens.get_token!(token_id_1).status == :available
        assert Tokens.get_token!(token_id_2).status == :active
        # Token 1 should only have user 1 in history
        assert length(history) == 1
      end
    end

    test "tokens at exact expiration boundary are released" do
      user_id = Ecto.UUID.generate()

      {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id

      # Set token started_at to exactly at the boundary
      exact_boundary = DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds, :second)

      TokenUsage
      |> where(token_id: ^token_id)
      |> Repo.update_all(set: [started_at: exact_boundary])

      # Run job - should release because `started_at <= deadline`
      {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      assert result.token_count == 1

      token = Tokens.get_token!(token_id)
      assert token.status == :available
    end

    test "tokens just before expiration boundary are NOT released" do
      user_id = Ecto.UUID.generate()

      {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id

      # Set token started_at to just before the boundary (1 second fresher)
      just_before_boundary =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds + 1, :second)

      TokenUsage
      |> where(token_id: ^token_id)
      |> Repo.update_all(set: [started_at: just_before_boundary])

      # Run job - should NOT release
      {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      assert result.token_count == 0

      token = Tokens.get_token!(token_id)
      assert token.status == :active
    end

    test "Oban job returns correct result structure" do
      user_id = Ecto.UUID.generate()
      {:ok, activation} = Tokens.activate_token(user_id)
      token_id = activation.token_id

      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      TokenUsage
      |> where(token_id: ^token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      # Job should return structured result
      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert is_map(result)
      assert Map.has_key?(result, :token_count)
      assert Map.has_key?(result, :usage_count)
      assert result.token_count == 1
      assert result.usage_count == 1
    end

    test "database consistency: all expired tokens released transactionally" do
      # Activate many tokens
      for _n <- 1..10 do
        Tokens.activate_token(Ecto.UUID.generate())
      end

      active_tokens = Tokens.list_active_tokens()
      assert length(active_tokens) == 10

      # Make all expired
      expired_time =
        DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds - 10, :second)

      TokenUsage
      |> where([u], is_nil(u.ended_at))
      |> Repo.update_all(set: [started_at: expired_time])

      # Run job
      {:ok, _result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      # Verify database consistency
      # All tokens should be available
      available_tokens = Tokens.list_available_tokens()
      refute Enum.empty?(available_tokens)

      active_tokens = Tokens.list_active_tokens()
      assert Enum.empty?(active_tokens)

      # All usage records should have ended_at set
      orphaned_usages =
        TokenUsage
        |> where([u], is_nil(u.ended_at))
        |> Repo.all()

      assert Enum.empty?(orphaned_usages)
    end
  end
end
