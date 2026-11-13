defmodule PuppyLog.Puppy.Changes.DueOnFromAge do
  @moduledoc """
  Sets `due_on` from `due_age`/`due_age_unit` and the puppy's birth date.

  Does nothing when no age is set. Without a birth date in the profile the
  entry cannot be dated, which is reported on `:due_age`.
  """

  use Ash.Resource.Change

  alias PuppyLog.Puppy
  alias PuppyLog.Puppy.DueAge

  @impl true
  def change(changeset, _opts, _context) do
    age = Ash.Changeset.get_attribute(changeset, :due_age)
    unit = Ash.Changeset.get_attribute(changeset, :due_age_unit)

    if is_nil(age) or is_nil(unit), do: changeset, else: set_due_on(changeset, age, unit)
  end

  defp set_due_on(changeset, age, unit) do
    case Puppy.get_profile(authorize?: false) do
      {:ok, %{birth_date: %Date{} = birth_date}} ->
        Ash.Changeset.force_change_attribute(
          changeset,
          :due_on,
          DueAge.due_on(birth_date, age, unit)
        )

      _ ->
        Ash.Changeset.add_error(changeset,
          field: :due_age,
          message: "Erst das Geburtsdatum im Profil eintragen"
        )
    end
  end
end
