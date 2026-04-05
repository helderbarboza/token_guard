defmodule TokenGuard.Repo.Migrations.AddUniqueActiveUsagePerUserIndex do
  use Ecto.Migration

  def change do
    create unique_index(:token_usages, [:user_id],
             where: "ended_at IS NULL",
             name: :unique_active_user_usage_index
           )
  end
end
