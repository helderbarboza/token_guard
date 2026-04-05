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
    |> validate_uuid_format()
  end

  defp validate_uuid_format(changeset) do
    validate_change(changeset, :user_id, fn :user_id, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _uuid} -> []
        :error -> [user_id: "must be a valid UUID"]
      end
    end)
  end
end
