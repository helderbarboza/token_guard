defmodule TokenGuard.TokensTest do
  use TokenGuard.DataCase, async: true

  alias TokenGuard.Repo
  alias TokenGuard.Tokens
  alias TokenGuard.Tokens.TokenUsage

  describe "token constraints" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "100 unique tokens are pre-generated" do
      assert length(Tokens.list_tokens()) == 100
    end

    test "all tokens start as available" do
      tokens = Tokens.list_tokens()
      assert Enum.all?(tokens, fn t -> t.status == :available end)
    end

    test "all tokens have unique UUIDs" do
      tokens = Tokens.list_tokens()
      ids = Enum.map(tokens, fn t -> t.id end)
      assert length(ids) == length(Enum.uniq(ids))
    end
  end

  describe "token activation" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "activating a token returns token_id and user_id" do
      user_id = Ecto.UUID.generate()
      {:ok, result} = Tokens.activate_token(user_id)

      assert result.token_id != nil
      assert result.user_id != nil
      assert is_binary(result.token_id)
      assert is_binary(result.user_id)
    end

    test "activating a token changes its status to active" do
      {:ok, result} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(result.token_id)

      assert token.status == :active
    end

    test "a user cannot have more than one active token - returns existing" do
      user_id = Ecto.UUID.generate()
      {:ok, activation1} = Tokens.activate_token(user_id)

      assert Tokens.get_active_usage_for_user(user_id) != nil
      assert length(Tokens.list_active_tokens()) == 1

      {:ok, activation2} = Tokens.activate_token(user_id)

      assert activation2.token_id == activation1.token_id
      assert length(Tokens.list_active_tokens()) == 1
      assert Tokens.get_active_usage_for_user(user_id) != nil
    end

    test "after releasing, user can activate a new token" do
      user_id = Ecto.UUID.generate()
      {:ok, activation1} = Tokens.activate_token(user_id)
      token1 = Tokens.get_token!(activation1.token_id)

      Tokens.release_token(token1)

      assert Tokens.get_active_usage_for_user(user_id) == nil

      {:ok, activation2} = Tokens.activate_token(user_id)
      assert activation2.token_id != activation1.token_id
      assert Tokens.get_active_usage_for_user(user_id) != nil
    end

    test "activating a token creates a usage record" do
      {:ok, result} = Tokens.activate_token(Ecto.UUID.generate())
      usage = Tokens.get_active_usage_for_token(result.token_id)

      assert usage != nil
      assert usage.user_id == result.user_id
      assert usage.started_at != nil
      assert usage.ended_at == nil
    end

    test "activating multiple tokens uses FIFO order" do
      # Get the first two available tokens to verify FIFO ordering
      available_before = Tokens.list_available_tokens()
      first_available = Enum.at(available_before, 0)
      second_available = Enum.at(available_before, 1)

      {:ok, first_activation} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, second_activation} = Tokens.activate_token(Ecto.UUID.generate())

      # Verify we got the expected tokens in FIFO order
      assert first_activation.token_id == first_available.id
      assert second_activation.token_id == second_available.id
    end

    test "activating 101st token reuses oldest active token via FIFO" do
      Tokens.release_all_active_tokens()

      for _n <- 1..100 do
        {:ok, _result} = Tokens.activate_token(Ecto.UUID.generate())
      end

      active_count = length(Tokens.list_active_tokens())
      assert active_count == 100

      oldest_before = List.first(Tokens.list_active_tokens())

      {:ok, result} = Tokens.activate_token(Ecto.UUID.generate())

      assert result.token_id != nil
      oldest_after = Tokens.get_token!(oldest_before.id)
      assert oldest_after.status == :available
    end

    test "activating 101st token releases oldest active token" do
      Tokens.release_all_active_tokens()

      for _n <- 1..100 do
        {:ok, _result} = Tokens.activate_token(Ecto.UUID.generate())
      end

      oldest_active = List.first(Tokens.list_active_tokens())
      oldest_id = oldest_active.id

      {:ok, _result} = Tokens.activate_token(Ecto.UUID.generate())

      old_token = Tokens.get_token!(oldest_id)
      assert old_token.status == :available
    end
  end

  describe "token usage history" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "a token can have multiple users in its history" do
      {:ok, first_activation} = Tokens.activate_token(Ecto.UUID.generate())
      token_id = first_activation.token_id
      first_user_id = first_activation.user_id

      token = Tokens.get_token!(token_id)
      Tokens.release_token(token)

      available_tokens = Tokens.list_available_tokens()
      same_token = Enum.find(available_tokens, fn t -> t.id == token_id end)
      assert same_token != nil, "Released token should be available again"

      {:ok, _result} = Tokens.activate_token(Ecto.UUID.generate())

      history = Tokens.get_token_history(token_id)
      user_ids = Enum.map(history, fn u -> u.user_id end)

      assert first_user_id in user_ids
    end

    test "only one active user at a time" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token_id = activation.token_id

      active_usage = Tokens.get_active_usage_for_token(token_id)
      assert active_usage != nil
      assert active_usage.user_id == activation.user_id
    end

    test "history shows ended_at for released users" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token_id = activation.token_id

      Tokens.release_token(Tokens.get_token!(token_id))

      history = Tokens.get_token_history(token_id)
      assert length(history) == 1
      assert history |> List.first() |> Map.get(:ended_at) != nil
    end
  end

  describe "token release" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "releasing a token changes status to available" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(activation.token_id)

      Tokens.release_token(token)

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == :available
    end

    test "releasing a token sets ended_at on usage" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token = Tokens.get_token!(activation.token_id)

      Tokens.release_token(token)

      usage = Tokens.get_active_usage_for_token(activation.token_id)
      assert usage == nil

      history = Tokens.get_token_history(activation.token_id)
      assert length(history) == 1
      assert history |> List.first() |> Map.get(:ended_at) != nil
    end

    test "release_all_active_tokens releases all active tokens" do
      Tokens.activate_token(Ecto.UUID.generate())
      Tokens.activate_token(Ecto.UUID.generate())
      Tokens.activate_token(Ecto.UUID.generate())

      assert length(Tokens.list_active_tokens()) == 3

      Tokens.release_all_active_tokens()

      assert Tokens.list_active_tokens() == []
      assert length(Tokens.list_available_tokens()) == 100
    end

    test "releasing expired tokens releases tokens active for > 2 minutes" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())
      token_id = activation.token_id

      yesterday = DateTime.add(DateTime.utc_now(), -121, :second)

      query = from(u in TokenUsage, where: u.token_id == ^token_id)
      Repo.update_all(query, set: [started_at: yesterday])

      Tokens.release_expired_tokens()

      updated_token = Tokens.get_token!(activation.token_id)
      assert updated_token.status == :available
    end

    test "token auto-release does NOT release tokens active for < 2 minutes" do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      Tokens.release_expired_tokens()

      token = Tokens.get_token!(activation.token_id)
      assert token.status == :active
    end
  end

  describe "list operations" do
    setup do
      Tokens.create_default_tokens()
      :ok
    end

    test "list_tokens returns all tokens" do
      assert length(Tokens.list_tokens()) == 100
    end

    test "list_available_tokens returns only available tokens" do
      Tokens.activate_token(Ecto.UUID.generate())
      Tokens.activate_token(Ecto.UUID.generate())

      available = Tokens.list_available_tokens()
      assert length(available) == 98
      assert Enum.all?(available, fn t -> t.status == :available end)
    end

    test "list_active_tokens returns only active tokens" do
      Tokens.activate_token(Ecto.UUID.generate())
      Tokens.activate_token(Ecto.UUID.generate())
      Tokens.activate_token(Ecto.UUID.generate())

      active = Tokens.list_active_tokens()
      assert length(active) == 3
      assert Enum.all?(active, fn t -> t.status == :active end)
    end
  end
end
