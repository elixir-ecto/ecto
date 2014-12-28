defmodule Ecto.Associations.NotLoaded do
  @moduledoc """
  Struct returned by one to one associations when there are not loaded.

  The fields are:

    * `:__field__` - the association field in `__owner__`
    * `:__owner__` - the model that owns the association

  """
  defstruct [:__field__, :__owner__]

  defimpl Inspect do
    def inspect(not_loaded, _opts) do
      msg = "association #{inspect not_loaded.__field__} is not loaded"
      ~s(#Ecto.Associations.NotLoaded<#{msg}>)
    end
  end
end

defmodule Ecto.Associations do
  @moduledoc false
end

defmodule Ecto.Reflections.HasOne do
  @moduledoc """
  The reflection record for a `has_one` association. Its fields are:

  * `field` - The name of the association field on the model;
  * `owner` - The model where the association was defined;
  * `associated` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """

  defstruct [:field, :owner, :assoc, :key, :assoc_key]
end

defmodule Ecto.Reflections.HasMany do
  @moduledoc """
  The struct record for a `has_many` association. Its fields are:

  * `field` - The name of the association field on the model;
  * `owner` - The model where the association was defined;
  * `assoc` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """

  defstruct [:field, :owner, :assoc, :key, :assoc_key]
end

defmodule Ecto.Reflections.BelongsTo do
  @moduledoc """
  The reflection struct for a `belongs_to` association. Its fields are:

  * `field` - The name of the association field on the model;
  * `owner` - The model where the association was defined;
  * `assoc` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `assoc` model used for the association;
  """

  defstruct [:field, :owner, :assoc, :key, :assoc_key]
end
