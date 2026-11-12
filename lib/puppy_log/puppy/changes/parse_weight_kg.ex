defmodule PuppyLog.Puppy.Changes.ParseWeightKg do
  @moduledoc """
  Sets `weight_grams` from the `weight_kg` argument, which is user input in
  German notation ("4,35", "4.35 kg").
  """

  use Ash.Resource.Change

  alias PuppyLog.Puppy.Weight

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.fetch_argument(changeset, :weight_kg) do
      {:ok, input} when is_binary(input) and input != "" ->
        case Weight.parse_kg(input) do
          {:ok, grams} ->
            Ash.Changeset.force_change_attribute(changeset, :weight_grams, grams)

          :error ->
            Ash.Changeset.add_error(changeset,
              field: :weight_kg,
              message: "bitte als Zahl eingeben, zum Beispiel 4,35"
            )
        end

      _ ->
        changeset
    end
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}
end
