defmodule Ecto.Reflections.HasOne do
  @moduledoc """
  The reflection record for a `has_one` association. Its fields are:

  * `field` - The name of the association field on the model;
  * `owner` - The model where the association was defined;
  * `associated` - The model that is associated;
  * `key` - The key on the `owner` model used for the association;
  * `assoc_key` - The key on the `associated` model used for the association;
  """
  
  defstruct [:field, :owner, :associated, :key, :assoc_key]
end

defmodule Ecto.Associations.HasOne do
  @moduledoc false

  defstruct [:loaded, :target, :name, :primary_key]
end

defmodule Ecto.Associations.HasOne.Proxy do
  @moduledoc """
  A has_one association.

  ## Create

  A new struct of the associated model can be created with `struct/2`. The
  created struct will have its foreign key set to the primary key of the parent
  model.

      defmodule Post do
        use Ecto.Model

        schema "posts" do
          has_one :permalink, Permalink
        end
      end

      post = put_primary_key(%Post{}, 42)
      struct(post.permalink, []) #=> %Permalink{post_id: 42}

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
                                       creating a an model with `new/2`);
  * `__assoc__(:primary_key, value, assoc)` - Sets the primary key;
  * `__assoc__(:new, name, target)` - Creates a new association with the given
                                      name and target;
  """

  @not_loaded :ECTO_NOT_LOADED

  require Ecto.Associations
  Ecto.Associations.defproxy(Ecto.Associations.HasOne)

  @doc false
  def __struct__(params \\ [], proxy(target: target, name: name, primary_key: pk_value)) do
    refl = target.__schema__(:association, name)
    fk = refl.assoc_key
    struct(refl.associated, [{fk, pk_value}] ++ params)
  end

  @doc """
  Returns the associated struct. Raises `AssociationNotLoadedError` if the
  association is not loaded.
  """
  def get(proxy(loaded: @not_loaded, target: target, name: name)) do
    refl = target.__schema__(:association, name)
    raise Ecto.AssociationNotLoadedError,
      type: :has_one, owner: refl.owner, name: name
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

defimpl Inspect, for: Ecto.Associations.HasOne do
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
    concat ["#Ecto.Associations.HasOne<", Inspect.List.inspect(kw, opts), ">"]
  end
end
