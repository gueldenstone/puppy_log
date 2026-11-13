defmodule PuppyLog.Puppy.Validations.AgeInRange do
  @moduledoc "Checks `due_age` against the range of its `due_age_unit` (see `PuppyLog.Puppy.DueAge.ranges/0`)."

  use Ash.Resource.Validation

  alias PuppyLog.Puppy.DueAge

  @impl true
  def validate(changeset, _opts, _context) do
    age = Ash.Changeset.get_attribute(changeset, :due_age)
    unit = Ash.Changeset.get_attribute(changeset, :due_age_unit)

    case DueAge.ranges() do
      %{^unit => range} when is_integer(age) ->
        if age in range,
          do: :ok,
          else: {:error, field: :due_age, message: "Wochen: 1 bis 104, Monate: 1 bis 36"}

      _ ->
        :ok
    end
  end
end
