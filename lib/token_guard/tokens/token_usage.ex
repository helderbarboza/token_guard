defmodule TokenGuard.Tokens.TokenUsage do
  @moduledoc """
  Schema for tracking token usage history.
  """

  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  typed_schema "token_usages" do
    field :user_id, Ecto.UUID
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    belongs_to :token, TokenGuard.Tokens.Token, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for validating token usage attributes.
  """
  def changeset(token_usage, attrs) do
    token_usage
    |> cast(attrs, [:id, :token_id, :user_id, :started_at, :ended_at])
    |> validate_required([:id, :token_id, :user_id, :started_at])
  end
end
