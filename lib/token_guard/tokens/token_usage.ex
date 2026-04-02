defmodule TokenGuard.Tokens.TokenUsage do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "token_usages" do
    field :user_identifier, :binary_id
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :token, TokenGuard.Tokens.Token, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:id, :token_id, :user_identifier, :started_at, :ended_at])
    |> validate_required([:id, :token_id, :user_identifier, :started_at])
  end
end
