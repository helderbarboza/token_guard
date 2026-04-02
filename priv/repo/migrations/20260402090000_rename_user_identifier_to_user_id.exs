defmodule TokenGuard.Repo.Migrations.RenameUserIdentifierToUserId do
  use Ecto.Migration

  def change do
    rename table(:token_usages), :user_identifier, to: :user_id
  end
end
