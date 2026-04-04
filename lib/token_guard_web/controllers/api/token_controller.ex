defmodule TokenGuardWeb.API.TokenController do
  @moduledoc """
  API controller for token management operations.
  Provides endpoints for activating, releasing, and viewing token status.
  """
  use TokenGuardWeb, :controller
  require Logger

  alias TokenGuard.Tokens
  alias TokenGuardWeb.API.ActivationParams

  @doc """
  Activates a token for a given user. If no available tokens exist,
  automatically releases the oldest active token to make room.
  """
  def activate(conn, params) do
    changeset = ActivationParams.changeset(params)

    if changeset.valid? do
      user_id = Ecto.Changeset.get_change(changeset, :user_id)
      Logger.debug("Token activation request", user_id: user_id)

      case Tokens.activate_token(user_id) do
        {:ok, result} ->
          Logger.info("Token activation successful",
            user_id: user_id,
            token_id: result.token_id
          )

          json(conn, %{token_id: result.token_id, user_id: result.user_id})

        {:error, reason} ->
          Logger.warning("Token activation failed",
            user_id: user_id,
            reason: reason
          )

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: Atom.to_string(reason)})
      end
    else
      errors = transform_errors(changeset)
      Logger.warning("Token activation validation failed", errors: errors)

      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: errors})
    end
  end

  defp transform_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _match, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Lists all tokens with their current status and timestamps.
  """
  def index(conn, _params) do
    tokens = Tokens.list_tokens()

    json(conn, %{
      tokens:
        Enum.map(tokens, fn token ->
          %{
            id: token.id,
            status: token.status,
            inserted_at: token.inserted_at,
            updated_at: token.updated_at
          }
        end)
    })
  end

  @doc """
  Returns detailed information about a specific token, including
  the currently active user if the token is in use.
  """
  def show(conn, %{"id" => id}) do
    with {:ok, id} <- validate_uuid(id),
         {:ok, token} <- fetch_token(id) do
      json(conn, %{
        id: token.id,
        status: token.status,
        active_user: active_user_info(token.id),
        inserted_at: token.inserted_at,
        updated_at: token.updated_at
      })
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid token ID format"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})
    end
  end

  defp fetch_token(id) do
    case Tokens.get_token_by_id(id) do
      nil -> {:error, :not_found}
      token -> {:ok, token}
    end
  end

  defp active_user_info(token_id) do
    case Tokens.get_active_usage_for_token(token_id) do
      nil -> nil
      usage -> %{user_id: usage.user_id, started_at: usage.started_at}
    end
  end

  @doc """
  Returns the usage history for a specific token, including all
  activation and deactivation events.
  """
  def history(conn, %{"id" => id}) do
    with {:ok, id} <- validate_uuid(id),
         {:ok, _token} <- fetch_token(id) do
      json(conn, %{history: token_history(id)})
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid token ID format"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})
    end
  end

  defp token_history(token_id) do
    token_id
    |> Tokens.get_token_history()
    |> Enum.map(fn usage ->
      %{
        user_id: usage.user_id,
        started_at: usage.started_at,
        ended_at: usage.ended_at
      }
    end)
  end

  defp validate_uuid(id) do
    case Ecto.UUID.dump(id) do
      {:ok, _uuid} -> {:ok, id}
      :error -> :error
    end
  end

  @doc """
  Releases all currently active tokens. Admin operation to force
  reset all tokens to available state.
  """
  def clear(conn, _params) do
    Logger.info("Admin request to release all active tokens")
    count = Tokens.release_all_active_tokens()

    json(conn, %{message: "#{count} token(s) released", released_count: count})
  end
end
