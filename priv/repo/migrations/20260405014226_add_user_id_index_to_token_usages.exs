defmodule TokenGuard.Repo.Migrations.AddUserIdIndexToTokenUsages do
  use Ecto.Migration

  def change do
    create index(:token_usages, [:user_id])
  end
end
