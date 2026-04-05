defmodule TokenGuard.ErrorHelpers do
  @moduledoc """
  Shared helpers for transforming Ecto changeset errors.
  """
  def transform_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _match, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  @doc """
  Maps internal error atoms to user-friendly error messages.
  """
  def error_message(:no_tokens_available), do: "No tokens are currently available. Please try again later."
  def error_message(:user_already_has_active_token), do: "User already has an active token."
  def error_message(_), do: "An unexpected error occurred. Please try again."
end
