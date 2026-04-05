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
end
