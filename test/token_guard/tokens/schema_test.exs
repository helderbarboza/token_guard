defmodule TokenGuard.Tokens.SchemaTest do
  use TokenGuard.DataCase, async: true

  alias TokenGuard.ErrorHelpers
  alias TokenGuard.Tokens.Token
  alias TokenGuard.Tokens.TokenUsage

  describe "Token changeset" do
    test "creates valid changeset with required fields" do
      token = %Token{id: Ecto.UUID.generate(), status: :available}
      changeset = Token.changeset(token, %{id: Ecto.UUID.generate(), status: :available})

      assert changeset.valid?
    end

    test "validates status is either available or active" do
      token = %Token{id: Ecto.UUID.generate(), status: :available}
      changeset = Token.changeset(token, %{id: Ecto.UUID.generate(), status: :invalid})

      refute changeset.valid?
      assert "is invalid" in changeset_errors(changeset).status
    end
  end

  describe "TokenUsage changeset" do
    test "creates valid changeset with required fields" do
      usage = %TokenUsage{
        id: Ecto.UUID.generate(),
        token_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        started_at: DateTime.utc_now(:second)
      }

      attrs = %{
        id: Ecto.UUID.generate(),
        token_id: Ecto.UUID.generate(),
        user_id: Ecto.UUID.generate(),
        started_at: DateTime.utc_now(:second)
      }

      changeset = TokenUsage.changeset(usage, attrs)
      assert changeset.valid?
    end
  end

  defp changeset_errors(changeset) do
    ErrorHelpers.transform_errors(changeset)
  end
end
