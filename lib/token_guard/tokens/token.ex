defmodule TokenGuard.Tokens.Token do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "tokens" do
    field :status, :string, default: "available"

    has_many :usages, TokenGuard.Tokens.TokenUsage, foreign_key: :token_id

    timestamps(type: :utc_datetime)
  end

  def status(:available), do: "available"
  def status(:active), do: "active"

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:id, :status])
    |> validate_required([:id, :status])
    |> validate_inclusion(:status, ["available", "active"])
  end
end
