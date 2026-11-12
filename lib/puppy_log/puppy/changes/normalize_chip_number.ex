defmodule PuppyLog.Puppy.Changes.NormalizeChipNumber do
  @moduledoc "Removes spaces and dashes so \"276 098 106 543 210\" is accepted."

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :chip_number) do
      value when is_binary(value) ->
        normalized = String.replace(value, ~r/[\s\-]/u, "")
        Ash.Changeset.force_change_attribute(changeset, :chip_number, blank_to_nil(normalized))

      _ ->
        changeset
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
