defmodule TokenGuard.Repo.Migrations.CreateTokens do
  use Ecto.Migration

  def change do
    create table(:tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :status, :string, null: false, default: "available"

      timestamps(type: :utc_datetime)
    end

    create index(:tokens, [:status])
  end
end
