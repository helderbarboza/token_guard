defmodule TokenGuard.Workers.ExpiredTokenReleaserTest do
  use TokenGuard.DataCase, async: true

  import Ecto.Query
  import ExUnit.CaptureLog

  alias TokenGuard.Repo
  alias TokenGuard.Tokens
  alias TokenGuard.Tokens.TokenUsage
  alias TokenGuard.Workers.ExpiredTokenReleaser

  @token_lifetime_ms Application.compile_env(:token_guard, :token_lifetime, :timer.minutes(2))
  @token_lifetime_seconds div(@token_lifetime_ms, 1000)
  @expired_offset_seconds @token_lifetime_seconds + 10

  describe "perform/1 - basic functionality" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "releases tokens that have been active for more than token lifetime" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(activation.token_id)

      assert token.status == :active

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert is_map(result)
      assert result.token_count == 1
      assert result.usage_count == 1

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == :available
    end

    test "does not release tokens active for less than token lifetime" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(activation.token_id)

      assert token.status == :active

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 0
      assert result.usage_count == 0

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == :active
    end

    test "releases multiple expired tokens" do
      {:ok, activation1} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, activation2} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, activation3} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      for act <- [activation1, activation2, activation3] do
        TokenUsage
        |> where(token_id: ^act.token_id)
        |> Repo.update_all(set: [started_at: expired_time])
      end

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 3
      assert result.usage_count == 3

      active_tokens = Tokens.list_active_tokens()
      assert Enum.empty?(active_tokens)
    end
  end

  describe "perform/1 - boundary conditions" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "releases token at exact expiration boundary" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      # Set to exactly at the boundary
      exact_boundary = DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: exact_boundary])

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 1

      token = Tokens.get_token!(activation.token_id)
      assert token.status == :available
    end

    test "does not release token just before expiration boundary" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      # Set to 1 second before boundary (still active)
      just_before = DateTime.add(DateTime.utc_now(:second), -@token_lifetime_seconds + 1, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: just_before])

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 0

      token = Tokens.get_token!(activation.token_id)
      assert token.status == :active
    end

    test "releases token well past expiration boundary" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      # Set to well past the boundary (1 hour ago)
      way_past = DateTime.add(DateTime.utc_now(:second), -3600, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: way_past])

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 1

      token = Tokens.get_token!(activation.token_id)
      assert token.status == :available
    end
  end

  describe "perform/1 - mixed scenarios" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "releases only expired tokens, preserves fresh tokens" do
      user_1 = Ecto.UUID.generate()
      user_2 = Ecto.UUID.generate()
      user_3 = Ecto.UUID.generate()

      {:ok, activation_1} = Tokens.activate_token(user_1)
      {:ok, activation_2} = Tokens.activate_token(user_2)
      {:ok, activation_3} = Tokens.activate_token(user_3)

      # Make only first two expired
      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      for token_id <- [activation_1.token_id, activation_2.token_id] do
        TokenUsage
        |> where(token_id: ^token_id)
        |> Repo.update_all(set: [started_at: expired_time])
      end

      # Third remains fresh

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 2
      assert result.usage_count == 2

      # Check statuses
      assert Tokens.get_token!(activation_1.token_id).status == :available
      assert Tokens.get_token!(activation_2.token_id).status == :available
      assert Tokens.get_token!(activation_3.token_id).status == :active

      # Check active users
      assert Tokens.get_active_usage_for_user(user_1) == nil
      assert Tokens.get_active_usage_for_user(user_2) == nil
      assert Tokens.get_active_usage_for_user(user_3) != nil
    end

    test "handles case with no expired tokens" do
      {:ok, activation_1} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, activation_2} = Tokens.activate_token(Ecto.UUID.generate())

      # Both remain fresh

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 0
      assert result.usage_count == 0

      assert Tokens.get_token!(activation_1.token_id).status == :active
      assert Tokens.get_token!(activation_2.token_id).status == :active
    end

    test "handles case with all expired tokens" do
      for _n <- 1..5 do
        Tokens.activate_token(Ecto.UUID.generate())
      end

      active_tokens = Tokens.list_active_tokens()
      assert length(active_tokens) == 5

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where([u], is_nil(u.ended_at))
      |> Repo.update_all(set: [started_at: expired_time])

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 5
      assert result.usage_count == 5

      active_tokens = Tokens.list_active_tokens()
      assert Enum.empty?(active_tokens)
    end

    test "handles empty pool with no active tokens" do
      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 0
      assert result.usage_count == 0
    end
  end

  describe "perform/1 - transactional integrity" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "marks usage record ended_at when releasing token" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      before_job = Tokens.get_active_usage_for_token(activation.token_id)
      assert before_job != nil
      assert before_job.ended_at == nil

      assert {:ok, _result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      after_job =
        TokenUsage
        |> where(token_id: ^activation.token_id)
        |> where([u], is_nil(u.ended_at) == false)
        |> Repo.one()

      assert after_job != nil
      assert after_job.ended_at != nil
    end

    test "token and usage records are updated atomically" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      assert {:ok, _result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      # Verify both are updated
      token = Tokens.get_token!(activation.token_id)
      assert token.status == :available

      usage =
        TokenUsage
        |> where(token_id: ^activation.token_id)
        |> Repo.one()

      assert usage.ended_at != nil

      # Verify we don't have orphaned records
      orphaned =
        TokenUsage
        |> where([u], is_nil(u.ended_at) and u.token_id == ^activation.token_id)
        |> Repo.all()

      assert Enum.empty?(orphaned)
    end

    test "idempotent: running job multiple times is safe" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      # Run job multiple times
      assert {:ok, result1} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result1.token_count == 1

      assert {:ok, result2} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result2.token_count == 0

      assert {:ok, result3} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result3.token_count == 0

      # Token should still be available
      token = Tokens.get_token!(activation.token_id)
      assert token.status == :available
    end
  end

  describe "perform/1 - logging" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "logs when job starts" do
      {:ok, _activation} = Tokens.activate_token(Ecto.UUID.generate())

      assert capture_log(fn ->
               ExpiredTokenReleaser.perform(%Oban.Job{})
             end) =~ "ExpiredTokenReleaser job started"
    end

    test "job is idempotent and can be retried" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      # First run
      job = %Oban.Job{attempt: 1}
      assert {:ok, result1} = ExpiredTokenReleaser.perform(job)
      assert result1.token_count == 1

      # Retry (second attempt)
      job_retry = %Oban.Job{attempt: 2}
      assert {:ok, result2} = ExpiredTokenReleaser.perform(job_retry)
      assert result2.token_count == 0

      # Should not error or cause issues
    end
  end

  describe "perform/1 - large scale operations" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "handles large batch of expired tokens efficiently" do
      # Create 50 expired tokens
      for _n <- 1..50 do
        {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

        expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

        TokenUsage
        |> where(token_id: ^activation.token_id)
        |> Repo.update_all(set: [started_at: expired_time])
      end

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 50
      assert result.usage_count == 50

      active_tokens = Tokens.list_active_tokens()
      assert Enum.empty?(active_tokens)
    end

    test "handles mixed batch with expired and fresh tokens" do
      # Create 50 total: 30 expired, 20 fresh
      for i <- 1..50 do
        {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

        if i <= 30 do
          expired_time =
            DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

          TokenUsage
          |> where(token_id: ^activation.token_id)
          |> Repo.update_all(set: [started_at: expired_time])
        end
      end

      assert {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})
      assert result.token_count == 30
      assert result.usage_count == 30

      active_tokens = Tokens.list_active_tokens()
      assert length(active_tokens) == 20
    end
  end

  describe "perform/1 - job structure" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "accepts Oban.Job struct and returns ok tuple" do
      job = %Oban.Job{
        id: 1,
        queue: "default",
        worker: "TokenGuard.Workers.ExpiredTokenReleaser",
        args: %{},
        attempt: 1,
        max_attempts: 1,
        state: :success,
        inserted_at: DateTime.utc_now()
      }

      result = ExpiredTokenReleaser.perform(job)
      assert match?({:ok, _}, result)
    end

    test "returns result map with token_count and usage_count keys" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where(token_id: ^activation.token_id)
      |> Repo.update_all(set: [started_at: expired_time])

      {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      assert is_map(result)
      assert Map.has_key?(result, :token_count)
      assert Map.has_key?(result, :usage_count)
      assert is_integer(result.token_count)
      assert is_integer(result.usage_count)
    end

    test "result counts match actual released tokens and usages" do
      for _n <- 1..3 do
        Tokens.activate_token(Ecto.UUID.generate())
      end

      expired_time = DateTime.add(DateTime.utc_now(:second), -@expired_offset_seconds, :second)

      TokenUsage
      |> where([u], is_nil(u.ended_at))
      |> Repo.update_all(set: [started_at: expired_time])

      {:ok, result} = ExpiredTokenReleaser.perform(%Oban.Job{})

      # Verify counts match reality
      available_count = length(Tokens.list_available_tokens())
      active_count = length(Tokens.list_active_tokens())

      assert result.token_count == 3
      assert result.usage_count == 3
      assert active_count == 0
      assert available_count == 100
    end
  end
end
