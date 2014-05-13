defmodule Ecto.Reflections.BelongsTo do
  @moduledoc """
  The reflection struct for a `belongs_to` association. Its fields are:

  * `field` - The name of the association field on the model;
  * `owner` - The model where the association was defined;
  * `associated` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """

  defstruct [:field, :owner, :associated, :key, :assoc_key]
end

defmodule Ecto.Associations.BelongsTo do
  @moduledoc false

  defstruct [:loaded, :target, :name]
end

defmodule Ecto.Associations.BelongsTo.Proxy do
  @moduledoc """
  A belongs_to association.

  ## Create

  A new struct of the associated model can be created with `struct/2`.

      defmodule Comment do
        use Ecto.Model

        schema "comments" do
          belongs_to :post, Post
        end
      end

      comment = %Comment{} 
      struct(comment.post, []) #=> %Post{}

  ## Reflection

  Any association module will generate the `__assoc__` function that can be
  used for runtime introspection of the association.

  * `__assoc__(:loaded, assoc)` - Returns the loaded entities or `:not_loaded`;
  * `__assoc__(:loaded, value, assoc)` - Sets the loaded entities;
  * `__assoc__(:target, assoc)` - Returns the model where the association was
                                  defined;
  * `__assoc__(:name, assoc)` - Returns the name of the association field on the
                                model;
  * `__assoc__(:new, name, target)` - Creates a new association with the given
                                      name and target;
  """

  @not_loaded :ECTO_NOT_LOADED

  require Ecto.Associations
  Ecto.Associations.defproxy(Ecto.Associations.BelongsTo)

  @doc false
  def __struct__(params \\ [], proxy(target: target, name: name)) do
    refl = target.__schema__(:association, name)
    struct(refl.associated, params)
  end

  @doc """
  Returns the associated struct. Raises `AssociationNotLoadedError` if the
  association is not loaded.
  """
  def get(proxy(loaded: @not_loaded, target: target, name: name)) do
    refl = target.__schema__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :belongs_to, owner: refl.owner, name: name
  end

  def get(proxy(loaded: loaded)) do
    loaded
  end

  @doc """
  Returns `true` if the association is loaded.
  """
  def loaded?(proxy(loaded: @not_loaded)), do: false
  def loaded?(_), do: true

  @doc false
  Enum.each [:loaded, :target, :name], fn field ->
    def __assoc__(unquote(field), record) do
      proxy([{unquote(field), var}]) = record
      var
    end
  end

  @doc false
  def __assoc__(:loaded, value, record) do
    proxy(record, [loaded: value])
  end

  def __assoc__(:new, name, target) do
    proxy(name: name, target: target, loaded: @not_loaded)
  end
end

defimpl Inspect, for: Ecto.Associations.BelongsTo do
  import Inspect.Algebra

  def inspect(%{name: name, target: target}, opts) do
    refl        = target.__schema__(:association, name)
    associated  = refl.associated
    foreign_key = refl.key
    references  = refl.assoc_key
    kw = [
      name: name,
      target: target,
      associated: associated,
      references: references,
      foreign_key: foreign_key
    ]
    concat ["#Ecto.Associations.BelongsTo<", Inspect.List.inspect(kw, opts), ">"]
  end
end
