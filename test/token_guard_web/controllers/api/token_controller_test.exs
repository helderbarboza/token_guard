defmodule TokenGuardWeb.API.TokenControllerTest do
  use TokenGuardWeb.ConnCase, async: true

  alias TokenGuard.Tokens

  describe "index" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "lists all tokens", %{conn: conn} do
      conn = get(conn, ~p"/api/tokens")

      response = json_response(conn, 200)
      assert is_list(response["tokens"])
      assert length(response["tokens"]) == 100
    end
  end

  describe "register" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "registers a token and returns token_id and user_id", %{conn: conn} do
      user_id = Ecto.UUID.generate()
      conn = post(conn, ~p"/api/tokens/register", user_id: user_id)

      response = json_response(conn, 200)
      assert response["token_id"] != nil
      assert response["user_id"] == user_id
    end

    test "returns error when missing user_id", %{conn: conn} do
      conn = post(conn, ~p"/api/tokens/register")

      assert json_response(conn, 422) == %{"errors" => %{"user_id" => ["is required"]}}
    end

    test "returns error when user_id is empty", %{conn: conn} do
      conn = post(conn, ~p"/api/tokens/register", user_id: "")

      assert json_response(conn, 422) == %{"errors" => %{"user_id" => ["is required"]}}
    end

    test "returns error when user_id is not a valid UUID", %{conn: conn} do
      conn = post(conn, ~p"/api/tokens/register", user_id: "not-a-uuid")

      assert json_response(conn, 422) == %{"errors" => %{"user_id" => ["must be a valid UUID"]}}
    end

    test "101st activation reuses oldest token via FIFO", %{conn: conn} do
      for _user_idx <- 1..100 do
        {:ok, _activation} = Tokens.activate_token(Ecto.UUID.generate())
      end

      assert length(Tokens.list_active_tokens()) == 100

      oldest_before = List.first(Tokens.list_active_tokens())

      new_user_id = Ecto.UUID.generate()
      conn = post(conn, ~p"/api/tokens/register", user_id: new_user_id)

      response = json_response(conn, 200)
      assert is_binary(response["token_id"])
      assert is_binary(response["user_id"])

      oldest_after = Tokens.get_token!(oldest_before.id)
      assert oldest_after.status == :available
    end
  end

  describe "show" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "returns token info without active user when available", %{conn: conn} do
      [token | _rest] = Tokens.list_tokens()

      conn = get(conn, ~p"/api/tokens/#{token.id}")

      response = json_response(conn, 200)
      assert response["id"] == token.id
      assert response["status"] == "available"
      assert response["active_user"] == nil
      assert is_binary(response["inserted_at"])
      assert is_binary(response["updated_at"])
    end

    test "returns token info with active user when active", %{conn: conn} do
      {:ok, activation} = Tokens.activate_token(Ecto.UUID.generate())

      conn = get(conn, ~p"/api/tokens/#{activation.token_id}")

      response = json_response(conn, 200)
      assert response["id"] == activation.token_id
      assert response["status"] == "active"
      assert response["active_user"]["user_id"] == activation.user_id
      assert is_binary(response["active_user"]["started_at"])
      assert is_binary(response["inserted_at"])
      assert is_binary(response["updated_at"])
    end

    test "returns 404 for non-existent token", %{conn: conn} do
      conn = get(conn, ~p"/api/tokens/00000000-0000-0000-0000-000000000000")

      assert json_response(conn, 404) == %{"error" => "Token not found"}
    end

    test "returns 400 for invalid UUID format", %{conn: conn} do
      conn = get(conn, ~p"/api/tokens/invalid-token-id")

      assert json_response(conn, 400) == %{"error" => "Invalid token ID format"}
    end
  end

  describe "history" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "returns empty history for token with no usage", %{conn: conn} do
      [token | _rest] = Tokens.list_tokens()

      conn = get(conn, ~p"/api/tokens/#{token.id}/history")

      assert json_response(conn, 200) == %{"history" => []}
    end

    test "returns usage history for token", %{conn: conn} do
      {:ok, activation1} = Tokens.activate_token(Ecto.UUID.generate())
      Tokens.release_token(Tokens.get_token!(activation1.token_id))
      {:ok, activation2} = Tokens.activate_token(Ecto.UUID.generate())

      conn = get(conn, ~p"/api/tokens/#{activation2.token_id}/history")

      response = json_response(conn, 200)
      assert response["history"] != []
    end

    test "returns 404 for non-existent token", %{conn: conn} do
      conn = get(conn, ~p"/api/tokens/00000000-0000-0000-0000-000000000000/history")

      assert json_response(conn, 404) == %{"error" => "Token not found"}
    end

    test "returns 400 for invalid UUID format", %{conn: conn} do
      conn = get(conn, ~p"/api/tokens/invalid-token-id/history")

      assert json_response(conn, 400) == %{"error" => "Invalid token ID format"}
    end
  end

  describe "clear" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "releases all active tokens", %{conn: conn} do
      {:ok, _activation1} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, _activation2} = Tokens.activate_token(Ecto.UUID.generate())
      {:ok, _activation3} = Tokens.activate_token(Ecto.UUID.generate())

      assert Tokens.list_active_tokens() != []

      conn = delete(conn, ~p"/api/tokens/active")

      assert json_response(conn, 200) == %{
               "message" => "3 token(s) released",
               "released_count" => 3
             }

      assert Tokens.list_active_tokens() == []
    end

    test "returns zero when no active tokens", %{conn: conn} do
      assert Tokens.list_active_tokens() == []

      conn = delete(conn, ~p"/api/tokens/active")

      assert json_response(conn, 200) == %{
               "message" => "0 token(s) released",
               "released_count" => 0
             }
    end
  end
end
