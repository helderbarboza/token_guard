defmodule TokenGuardWeb.API.TokenControllerTest do
  use TokenGuardWeb.ConnCase, async: true

  alias TokenGuard.Tokens

  describe "clear" do
    setup do
      Tokens.create_tokens(100)
      :ok
    end

    test "releases all active tokens", %{conn: conn} do
      {:ok, _activation1} = Tokens.activate_token()
      {:ok, _activation2} = Tokens.activate_token()
      {:ok, _activation3} = Tokens.activate_token()

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
