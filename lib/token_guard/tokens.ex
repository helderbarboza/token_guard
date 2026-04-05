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

  @doc """
  Retrieves all tokens from the database.

  Returns a list of all tokens regardless of their status.
  """
  @spec list_tokens() :: [Token.t()]
  def list_tokens do
    Repo.all(Token)
  end

  @doc """
  Retrieves all tokens with available status.

  Returns a list of tokens sorted by insertion time, representing tokens
  that are not currently in use and can be activated.
  """
  @spec list_available_tokens() :: [Token.t()]
  def list_available_tokens do
    Token
    |> where(status: :available)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Retrieves all tokens with active status.

  Returns a list of tokens sorted by insertion time, representing tokens
  that are currently assigned to users.
  """
  @spec list_active_tokens() :: [Token.t()]
  def list_active_tokens do
    Token
    |> where(status: :active)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @doc """
  Retrieves a token by ID, raising an error if not found.

  ## Parameters
    * `id` - The token ID to retrieve

  ## Raises
    * Raises `Ecto.NoResultsError` if the token does not exist.
  """
  @spec get_token!(token_id()) :: Token.t()
  def get_token!(id) do
    Repo.get!(Token, id)
  end

  @doc """
  Retrieves a token by ID, returning nil if not found.

  ## Parameters
    * `id` - The token ID to retrieve

  ## Returns
    * A `Token.t()` struct if found, or `nil` otherwise.
  """
  @spec get_token_by_id(token_id()) :: Token.t() | nil
  def get_token_by_id(id) do
    Repo.get(Token, id)
  end

  @doc """
  Retrieves the active (ongoing) usage record for a specific token.

  Returns the current usage session for the token, or nil if no active session exists.

  ## Parameters
    * `token_id` - The token ID to find active usage for
  """
  @spec get_active_usage_for_token(token_id()) :: TokenUsage.t() | nil
  def get_active_usage_for_token(token_id) do
    TokenUsage
    |> where(token_id: ^token_id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.one()
  end

  @doc """
  Retrieves the active (ongoing) token usage record for a specific user.

  Returns the current token session assigned to the user, or nil if the user
  has no active token.

  ## Parameters
    * `user_id` - The user ID to find active token usage for
  """
  @spec get_active_usage_for_user(user_id()) :: TokenUsage.t() | nil
  def get_active_usage_for_user(user_id) do
    TokenUsage
    |> where(user_id: ^user_id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.one()
  end

  @doc """
  Retrieves the complete usage history for a token.

  Returns all past and present usage records for the token, sorted by
  start time in descending order (most recent first).

  ## Parameters
    * `token_id` - The token ID to retrieve history for
  """
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
    result = Repo.transaction(fn -> perform_activation(user_id) end)

    case result do
      {:ok, %{token_id: token_id, user_id: _user_id}} ->
        Logger.info("Token activation successful", token_id: token_id, user_id: user_id)
        {:ok, %{token_id: token_id, user_id: user_id}}

      {:error, :no_tokens_available} ->
        Logger.warning("No tokens available for user", user_id: user_id)
        {:error, :no_tokens_available}

      {:error, reason} ->
        Logger.error("Unexpected token activation error",
          user_id: user_id,
          reason: inspect(reason)
        )

        {:error, :unexpected_error}
    end
  end

  defp perform_activation(user_id) do
    case get_active_usage_for_user(user_id) do
      %{token_id: existing_token_id} ->
        Logger.info("User already has active token, returning existing",
          user_id: user_id,
          token_id: existing_token_id
        )

        %{token_id: existing_token_id, user_id: user_id}

      nil ->
        acquire_and_activate_token(user_id)
    end
  end

  defp acquire_and_activate_token(user_id) do
    token = fetch_available_token() || release_oldest_active_token()

    if token do
      activate_token_record(token, user_id)
    else
      Repo.rollback(:no_tokens_available)
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
    update_token_status(token)
    create_token_usage_record(token.id, user_id, now)
    %{token_id: token.id, user_id: user_id}
  end

  defp update_token_status(token) do
    token
    |> Ecto.Changeset.change(status: :active)
    |> Repo.update!()
  end

  defp create_token_usage_record(token_id, user_id, started_at) do
    attrs = %{
      token_id: token_id,
      user_id: user_id,
      started_at: started_at
    }

    changeset = TokenUsage.changeset(%TokenUsage{}, attrs)
    Repo.insert!(changeset)
  end

  defp release_oldest_active_token do
    Token
    |> where(status: :active)
    |> order_by(asc: :inserted_at)
    |> limit(1)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.one()
    |> then(fn
      nil -> nil
      token -> release_token(token)
    end)
  end

  @doc """
  Releases a token back to available status and marks any active usage as ended.
  Used when a user explicitly releases their token or when it expires.
  """
  @spec release_token(Token.t()) :: Token.t()
  def release_token(token) do
    now = DateTime.utc_now(:second)

    {:ok, updated_token} =
      token
      |> Ecto.Changeset.change(status: :available)
      |> Repo.update()

    TokenUsage
    |> where(token_id: ^updated_token.id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.update_all(set: [ended_at: now])

    Logger.info("Token released", token_id: updated_token.id)
    updated_token
  end

  @doc """
  Finds all tokens that have been active beyond the configured token lifetime
  and releases them. Called periodically by the background worker to enforce
  automatic token expiration.
  """
  @spec release_expired_tokens() ::
          {:ok, %{token_count: non_neg_integer(), usage_count: non_neg_integer()}}
          | {:error, term()}
  def release_expired_tokens do
    now = DateTime.utc_now(:second)
    token_lifetime = Application.get_env(:token_guard, :token_lifetime, :timer.minutes(2))
    deadline = DateTime.add(DateTime.utc_now(), -token_lifetime, :millisecond)

    expired_usage_ids =
      TokenUsage
      |> where([u], is_nil(u.ended_at) and u.started_at <= ^deadline)
      |> select([u], u.token_id)
      |> Repo.all()

    if Enum.empty?(expired_usage_ids) do
      {:ok, %{token_count: 0, usage_count: 0}}
    else
      multi =
        Ecto.Multi.new()
        |> Ecto.Multi.update_all(
          :update_tokens,
          where(Token, [t], t.id in ^expired_usage_ids),
          set: [status: :available]
        )
        |> Ecto.Multi.update_all(
          :update_usages,
          where(TokenUsage, [u], is_nil(u.ended_at) and u.started_at <= ^deadline),
          set: [ended_at: now]
        )

      case Repo.transaction(multi) do
        {:ok, %{update_tokens: {token_count, nil}, update_usages: {usage_count, nil}}} ->
          Logger.info("Expired tokens released",
            token_count: token_count,
            usage_count: usage_count,
            deadline: deadline
          )

          {:ok, %{token_count: token_count, usage_count: usage_count}}

        {:error, _operation, reason, _changes} ->
          Logger.error("Failed to release expired tokens", reason: inspect(reason))
          {:error, reason}
      end
    end
  end

  @doc """
  Releases all currently active tokens back to available status.

  Transitions all tokens with active status back to available and marks
  all associated usage records as ended. Returns the count of tokens released.
  Useful for administrative operations like maintenance or system resets.
  """
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
  Creates the default number of tokens and adds them to the database.

  Uses the `@default_token_count` module attribute to determine how many
  tokens to create. All tokens are created with `:available` status.

  ## Returns
    * A tuple `{count, nil}` where count is the number of tokens created.
  """
  @spec create_default_tokens() :: {non_neg_integer(), [any()]}
  def create_default_tokens do
    create_tokens(@default_token_count)
  end

  @doc """
  Creates the specified number of tokens and adds them to the database.

  Batch inserts multiple tokens with `:available` status. This is more efficient
  than creating tokens individually for bulk token generation.

  ## Parameters
    * `count` - The number of tokens to create

  ## Returns
    * A tuple `{count, nil}` where count is the number of tokens successfully created.
  """
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
