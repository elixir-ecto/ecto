defmodule Ecto.Reflections.HasMany do
  @moduledoc """
  The struct record for a `has_many` association. Its fields are:

  * `field` - The name of the association field on the model;
  * `owner` - The model where the association was defined;
  * `associated` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """
  
  defstruct [:field, :owner, :associated, :key, :assoc_key]
end

defmodule Ecto.Associations.HasMany do
  @moduledoc false

  defstruct [:loaded, :target, :name, :primary_key]
end

defmodule Ecto.Associations.HasMany.Proxy do
  @moduledoc """
  A has_many association.

  ## Create

  A new struct of the associated model can be created with `struct/2`. The
  created struct will have its foreign key set to the primary key of the parent
  model.

      defmodule Post do
        use Ecto.Model

        schema "posts" do
          has_many :comments, Comment
        end
      end

      post = put_primary_key(%Post{}, 42)
      struct(post.comments, []) #=> %Comment{post_id: 42}

  ## Reflection

  Any association module will generate the `__assoc__` function that can be
  used for runtime introspection of the association.

  * `__assoc__(:loaded, assoc)` - Returns the loaded entities or `:not_loaded`;
  * `__assoc__(:loaded, value, assoc)` - Sets the loaded entities;
  * `__assoc__(:target, assoc)` - Returns the model where the association was
                                  defined;
  * `__assoc__(:name, assoc)` - Returns the name of the association field on the
                                model;
  * `__assoc__(:primary_key, assoc)` - Returns the primary key (used when
                                       creating a model with `new/2`);
  * `__assoc__(:primary_key, value, assoc)` - Sets the primary key;
  * `__assoc__(:new, name, target)` - Creates a new association with the given
                                      name and target;
  """

  require Ecto.Associations
  require Ecto.Query

  @not_loaded :ECTO_NOT_LOADED

  Ecto.Associations.defproxy(Ecto.Associations.HasMany)

  @doc false
  def __struct__(params \\ [], proxy(target: target, name: name, primary_key: pk_value)) do
    refl = target.__schema__(:association, name)
    fk = refl.assoc_key
    struct(refl.associated, [{fk, pk_value}] ++ params)
  end

  @doc """
  Returns a list of the associated structs. Raises `AssociationNotLoadedError`
  if the association is not loaded.
  """
  def all(proxy(loaded: @not_loaded, target: target, name: name)) do
    refl = target.__schema__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_many, owner: refl.owner, name: name
  end

  def all(proxy(loaded: loaded)) do
    loaded
  end

  @doc """
  Returns `true` if the association is loaded.
  """
  def loaded?(proxy(loaded: @not_loaded)), do: false
  def loaded?(_), do: true

  def __queryable__(proxy(target: target, name: name, primary_key: pk)) do
    refl = target.__schema__(:association, name)

    Ecto.Query.from x in refl.associated,
             where: field(x, ^refl.assoc_key) == ^pk
  end

  @doc false
  Enum.each [:loaded, :target, :name, :primary_key], fn field ->
    def __assoc__(unquote(field), record) do
      proxy([{unquote(field), var}]) = record
      var
    end
  end

  @doc false
  Enum.each [:loaded, :primary_key], fn field ->
    def __assoc__(unquote(field), value, record) do
      proxy(record, [{unquote(field), value}])
    end
  end

  def __assoc__(:new, name, target) do
    proxy(name: name, target: target, loaded: @not_loaded)
  end
end

defimpl Enumerable, for: Ecto.Associations.HasMany do
  def count(assoc), do: {:ok, length(assoc.get)}
  def member?(assoc, value), do: value in assoc.get
  def reduce(assoc, acc, fun), do: Enumerable.List.reduce(assoc.get, acc, fun)
end

defimpl Inspect, for: Ecto.Associations.HasMany do
  import Inspect.Algebra

  def inspect(%{name: name, target: target}, opts) do
    refl        = target.__schema__(:association, name)
    associated  = refl.associated
    references  = refl.key
    foreign_key = refl.assoc_key
    kw = [
      name: name,
      target: target,
      associated: associated,
      references: references,
      foreign_key: foreign_key
    ]
    concat ["#Ecto.Associations.HasMany<", Inspect.List.inspect(kw, opts), ">"]
  end
end
