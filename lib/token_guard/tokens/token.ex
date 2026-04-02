defmodule TokenGuard.Tokens.Token do
  @moduledoc """
  Schema for tokens that can be activated for use.
  """

  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  typed_schema "tokens", opaque: true do
    field :status, :string, default: "available", null: false

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
