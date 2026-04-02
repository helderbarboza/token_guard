defmodule TokenGuard.Tokens do
  @moduledoc """
  Context module for managing tokens and their usage.
  """
  import Ecto.Query
  alias TokenGuard.Repo
  alias TokenGuard.Tokens.Token
  alias TokenGuard.Tokens.TokenUsage

  @token_lifetime_seconds 120

  def generate_uuid, do: UUID.uuid4()

  def list_tokens do
    Repo.all(Token)
  end

  def list_available_tokens do
    Token
    |> where(status: "available")
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def list_active_tokens do
    Token
    |> where(status: "active")
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  def get_token!(id) do
    Repo.get!(Token, id)
  end

  def get_token_by_id(id) do
    Repo.get(Token, id)
  end

  def get_token_with_active_usage(token_id) do
    token = Repo.get!(Token, token_id)
    usage = get_active_usage_for_token(token_id)
    %{token: token, active_usage: usage}
  end

  def get_active_usage_for_token(token_id) do
    TokenUsage
    |> where(token_id: ^token_id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.one()
  end

  def get_token_history(token_id) do
    TokenUsage
    |> where(token_id: ^token_id)
    |> order_by(desc: :started_at)
    |> Repo.all()
  end

  def activate_token do
    Repo.transaction(fn ->
      token = fetch_available_token() || release_oldest_active_token()

      if token do
        activate_token_record(token)
      else
        Repo.rollback(:no_tokens_available)
      end
    end)
  end

  defp fetch_available_token do
    Token
    |> where(status: "available")
    |> order_by(asc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  defp activate_token_record(token) do
    user_id = generate_uuid()
    now = DateTime.utc_now(:second)

    usage = %TokenUsage{
      id: generate_uuid(),
      token_id: token.id,
      user_identifier: user_id,
      started_at: now
    }

    token
    |> Ecto.Changeset.change(status: "active")
    |> Repo.update!()

    Repo.insert!(usage)

    %{token_id: token.id, user_id: user_id}
  end

  defp release_oldest_active_token do
    Token
    |> where(status: "active")
    |> order_by(asc: :inserted_at)
    |> limit(1)
    |> Repo.one()
    |> release_token()
  end

  def release_token(token) do
    now = DateTime.utc_now(:second)

    token
    |> Ecto.Changeset.change(status: "available")
    |> Repo.update!()

    TokenUsage
    |> where(token_id: ^token.id)
    |> where([u], is_nil(u.ended_at))
    |> Repo.all()
    |> Enum.each(fn usage ->
      usage
      |> Ecto.Changeset.change(ended_at: now)
      |> Repo.update!()
    end)

    token
  end

  def release_expired_tokens do
    deadline = DateTime.add(DateTime.utc_now(), -@token_lifetime_seconds, :second)

    expired_tokens =
      Token
      |> join(:inner, [t], u in TokenUsage, on: t.id == u.token_id and is_nil(u.ended_at))
      |> where([t, u], u.started_at <= ^deadline)
      |> select([t, u], t)
      |> Repo.all()

    Enum.each(expired_tokens, fn token ->
      release_token(token)
    end)
  end

  def release_all_active_tokens do
    active = list_active_tokens()

    Enum.each(active, fn token ->
      release_token(token)
    end)
  end

  def create_tokens(count) do
    now = DateTime.utc_now(:second)

    tokens =
      for _n <- 1..count do
        %{
          id: generate_uuid(),
          status: "available",
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(Token, tokens)
  end
end
