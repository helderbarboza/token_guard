defmodule TokenGuardWeb.API.TokenController do
  use TokenGuardWeb, :controller
  require Logger

  alias TokenGuard.Tokens
  alias TokenGuardWeb.API.ActivationParams

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
                user_id: usage.user_id,
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
                user_id: usage.user_id,
                started_at: usage.started_at,
                ended_at: usage.ended_at
              }
            end)
        })
    end
  end

  def clear(conn, _params) do
    Logger.info("Admin request to release all active tokens")
    count = Tokens.release_all_active_tokens()

    json(conn, %{message: "#{count} token(s) released", released_count: count})
  end
end
