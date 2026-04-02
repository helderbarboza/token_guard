defmodule TokenGuard.Repo.Migrations.CreateTokenUsages do
  use Ecto.Migration

  def change do
    create table(:token_usages, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :token_id, references(:tokens, type: :uuid, on_delete: :delete_all), null: false
      add :user_identifier, :uuid, null: false
      add :started_at, :utc_datetime, null: false, default: fragment("NOW()")
      add :ended_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:token_usages, [:token_id])
    create index(:token_usages, [:started_at])
  end
end
