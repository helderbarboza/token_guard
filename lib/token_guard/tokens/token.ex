defmodule TokenGuard.Tokens.Token do
  @moduledoc """
  Schema for tokens that can be activated for use.
  """

  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @status_values [:available, :active]

  typed_schema "tokens" do
    field :status, Ecto.Enum, values: @status_values, default: :available, null: false

    has_many :usages, TokenGuard.Tokens.TokenUsage, foreign_key: :token_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for validating token attributes.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @status_values)
  end
end
