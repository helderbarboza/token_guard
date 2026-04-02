defmodule TokenGuardWeb.API.ActivationParams do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  schema "activation_params" do
    field :user_id, :string
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [:user_id])
    |> validate_required(:user_id, message: "is required")
    |> validate_format(
      :user_id,
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      message: "must be a valid UUID"
    )
  end
end
