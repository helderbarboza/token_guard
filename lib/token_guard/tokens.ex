defmodule TokenGuard.Tokens do
  @moduledoc """
  Context module for managing tokens and their usage.
  """
  import Ecto.Query
  require Logger

  alias TokenGuard.Repo
  alias TokenGuard.Tokens.Token
  alias TokenGuard.Tokens.TokenUsage

  @default_token_count 100

  @type token_id :: binary()
  @type user_id :: binary()

  @spec list_tokens() :: [Token.t()]
  def list_tokens do
    Repo.all(Token)
  end

  @spec list_available_tokens() :: [Token.t()]
  def list_available_tokens do
    Token
    |> where(status: :available)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @spec list_active_tokens() :: [Token.t()]
  def list_active_tokens do
    Token
    |> where(status: :active)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @spec get_token!(token_id()) :: Token.t()
  def get_token!(id) do
    Repo.get!(Token, id)
  end

  @spec get_token_by_id(token_id()) :: Token.t() | nil
  def get_token_by_id(id) do
    Repo.get(Token, id)
  end

  @spec get_token_with_active_usage(token_id()) :: %{
          token: Token.t(),
          active_usage: TokenUsage.t() | nil
        }
  def get_token_with_active_usage(token_id) do
    token = Repo.get!(Token, token_id)
    usage = get_active_usage_for_token(token_id)
    %{token: token, active_usage: usage}
  end

  @spec get_active_usage_for_token(token_id()) :: TokenUsage.t() | nil
  def get_active_usage_for_token(token_id) do
    TokenUsage
    |> where(token_id: ^token_id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.one()
  end

  @spec get_active_usage_for_user(user_id()) :: TokenUsage.t() | nil
  def get_active_usage_for_user(user_id) do
    TokenUsage
    |> where(user_id: ^user_id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.one()
  end

  @spec get_token_history(token_id()) :: [TokenUsage.t()]
  def get_token_history(token_id) do
    TokenUsage
    |> where(token_id: ^token_id)
    |> order_by(desc: :started_at)
    |> Repo.all()
  end

  @doc """
  Activates a token for the given user.

  First attempts to use an available token;
  if none available, releases the oldest active token. Returns the token_id and user_id
  on success, or `:no_tokens_available` error if no tokens can be activated.
  If the user already has an active token, returns that existing token.
  """
  @spec activate_token(user_id()) ::
          {:ok, %{token_id: token_id(), user_id: user_id()}} | {:error, atom()}
  def activate_token(user_id) do
    case get_active_usage_for_user(user_id) do
      %{token_id: existing_token_id} ->
        Logger.info("User already has active token, returning existing",
          user_id: user_id,
          token_id: existing_token_id
        )

        {:ok, %{token_id: existing_token_id, user_id: user_id}}

      nil ->
        do_activate_token(user_id)
    end
  end

  defp do_activate_token(user_id) do
    result =
      Repo.transaction(fn ->
        token = fetch_available_token() || release_oldest_active_token()

        if token do
          activate_token_record(token, user_id)
        else
          Repo.rollback(:no_tokens_available)
        end
      end)

    case result do
      {:ok, %{token_id: token_id, user_id: ^user_id}} ->
        Logger.info("Token activated", token_id: token_id, user_id: user_id)
        {:ok, %{token_id: token_id, user_id: user_id}}

      {:error, :no_tokens_available} ->
        Logger.warning("No tokens available for user", user_id: user_id)
        {:error, :no_tokens_available}
    end
  end

  defp fetch_available_token do
    Token
    |> where(status: :available)
    |> order_by(asc: :inserted_at)
    |> limit(1)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.one()
  end

  defp activate_token_record(token, user_id) do
    now = DateTime.utc_now()

    attrs = %{
      token_id: token.id,
      user_id: user_id,
      started_at: now
    }

    changeset = TokenUsage.changeset(%TokenUsage{}, attrs)

    token
    |> Ecto.Changeset.change(status: :active)
    |> Repo.update!()

    case Repo.insert(changeset) do
      {:ok, _usage} ->
        %{token_id: token.id, user_id: user_id}

      {:error, _changeset} ->
        Repo.rollback(:user_already_has_active_token)
    end
  end

  defp release_oldest_active_token do
    Token
    |> where(status: :active)
    |> order_by(asc: :inserted_at)
    |> limit(1)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.one()
    |> case do
      nil -> nil
      token -> release_token(token)
    end
  end

  @doc """
  Releases a token back to available status and marks any active usage as ended.
  Used when a user explicitly releases their token or when it expires.
  """
  @spec release_token(Token.t()) :: Token.t()
  def release_token(token) do
    now = DateTime.utc_now(:second)

    token
    |> Ecto.Changeset.change(status: :available)
    |> Repo.update!()

    TokenUsage
    |> where(token_id: ^token.id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.update_all(set: [ended_at: now])

    Logger.info("Token released", token_id: token.id)
    token
  end

  @doc """
  Finds all tokens that have been active beyond the configured token lifetime
  and releases them. Called periodically by the background worker to enforce
  automatic token expiration.
  """
  @spec release_expired_tokens() :: :ok
  def release_expired_tokens do
    now = DateTime.utc_now(:second)
    token_lifetime = Application.get_env(:token_guard, :token_lifetime, :timer.minutes(2))
    deadline = DateTime.add(DateTime.utc_now(), -token_lifetime, :millisecond)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :update_tokens,
        Token
        |> join(:inner, [t], u in TokenUsage, on: t.id == u.token_id and is_nil(u.ended_at))
        |> where([t, u], u.started_at <= ^deadline)
        |> where(status: :active),
        set: [status: :available]
      )
      |> Ecto.Multi.update_all(
        :update_usages,
        TokenUsage
        |> join(:inner, [u], t in Token, on: t.id == u.token_id and t.status == :available)
        |> where([u, t], u.started_at <= ^deadline and is_nil(u.ended_at)),
        set: [ended_at: now]
      )

    case Repo.transaction(multi) do
      {:ok, %{update_tokens: {token_count, nil}, update_usages: {usage_count, nil}}} ->
        Logger.info("Expired tokens released",
          token_count: token_count,
          usage_count: usage_count,
          deadline: deadline
        )

      {:error, _operation, _changeset, _changes} ->
        Logger.error("Failed to release expired tokens")
    end

    :ok
  end

  @spec release_all_active_tokens() :: non_neg_integer()
  def release_all_active_tokens do
    now = DateTime.utc_now(:second)

    multi =
      Ecto.Multi.new()
      |> Ecto.Multi.update_all(
        :update_tokens,
        where(Token, status: :active),
        set: [status: :available]
      )
      |> Ecto.Multi.update_all(
        :update_usages,
        TokenUsage
        |> join(:inner, [u], t in Token, on: t.id == u.token_id and t.status == :available)
        |> where([u, t], is_nil(u.ended_at)),
        set: [ended_at: now]
      )

    case Repo.transaction(multi) do
      {:ok, %{update_tokens: {token_count, nil}, update_usages: {usage_count, nil}}} ->
        Logger.info("Admin released all active tokens",
          token_count: token_count,
          usage_count: usage_count
        )

        token_count

      {:error, _operation, _changeset, _changes} ->
        Logger.error("Failed to release all active tokens")
        0
    end
  end

  @doc """
  Creates the default number of tokens.
  """
  @spec create_default_tokens() :: {non_neg_integer(), [any()]}
  def create_default_tokens do
    create_tokens(@default_token_count)
  end

  @spec create_tokens(non_neg_integer()) :: {non_neg_integer(), [any()]}
  def create_tokens(count) do
    now = DateTime.utc_now(:second)

    tokens =
      for _n <- 1..count do
        %{
          status: :available,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Token, tokens)
  end
end
