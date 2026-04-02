defmodule TokenGuardWeb.API.TokenController do
  use TokenGuardWeb, :controller

  alias TokenGuard.Tokens

  def activate(conn, %{"user_id" => user_id}) do
    if valid_uuid?(user_id) do
      case Tokens.activate_token(user_id) do
        {:ok, result} ->
          json(conn, %{token_id: result.token_id, user_id: result.user_id})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: Atom.to_string(reason)})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "user_id must be a valid UUID"})
    end
  end

  def activate(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "user_id is required"})
  end

  defp valid_uuid?(string) do
    case Ecto.UUID.cast(string) do
      {:ok, _uuid} -> true
      :error -> false
    end
  end

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

  def show(conn, %{"id" => id}) do
    case Tokens.get_token_by_id(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})

      token ->
        usage = Tokens.get_active_usage_for_token(id)

        json(conn, %{
          id: token.id,
          status: token.status,
          active_user:
            if(usage) do
              %{
                user_id: usage.user_identifier,
                started_at: usage.started_at
              }
            else
              nil
            end,
          inserted_at: token.inserted_at,
          updated_at: token.updated_at
        })
    end
  end

  def history(conn, %{"id" => id}) do
    case Tokens.get_token_by_id(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Token not found"})

      _token ->
        history = Tokens.get_token_history(id)

        json(conn, %{
          history:
            Enum.map(history, fn usage ->
              %{
                user_id: usage.user_identifier,
                started_at: usage.started_at,
                ended_at: usage.ended_at
              }
            end)
        })
    end
  end

  def clear(conn, _params) do
    count = Tokens.release_all_active_tokens()

    json(conn, %{message: "#{count} token(s) released", released_count: count})
  end
end
