defmodule PuppyLog.Puppy.Validations.OnlyFor do
  @moduledoc """
  Rejects a value in `field` unless the entry's `kind` is one of `kinds`.
  The error is attached to `field`, so forms show it on the right input.
  """

  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    field = Keyword.fetch!(opts, :field)
    kind = Ash.Changeset.get_attribute(changeset, :kind)

    cond do
      is_nil(Ash.Changeset.get_attribute(changeset, field)) -> :ok
      kind in Keyword.fetch!(opts, :kinds) -> :ok
      true -> {:error, field: field, message: Keyword.fetch!(opts, :message)}
    end
  end
end
