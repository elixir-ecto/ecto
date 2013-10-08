defmodule Ecto.Model do
  @moduledoc """
  Used to define a model. See `Ecto.Model.Queryable`, that is imported when
  `Ecto.Model` is used, for how to define a queryable model.
  """

  defmacro __using__(_opts) do
    quote do
      import Ecto.Model.Queryable
    end
  end
end

defmodule Ecto.Model.Queryable do
  @moduledoc """
  Macros for defining a queryable model. A name for the queryable is given (for
  example the table name in a SQL database) and the `Ecto.Entity` to be used.
  """

  @doc """
  Defines a queryable name and its entity.

  ## Example

      defmodule Post do
        use Ecto.Model
        queryable "posts", Post.Entity
      end
  """
  defmacro queryable(name, { :__aliases__, _, _ } = entity) do
    quote bind_quoted: [name: name, entity: entity] do
      def new(), do: unquote(entity).new()
      def new(params), do: unquote(entity).new(params)
      def __model__(:name), do: unquote(name)
      def __model__(:entity), do: unquote(entity)
    end
  end

  @doc """
  Defines a queryable name and the entity definition inline. `opts` will be
  given to the `use Ecto.Entity` call, see `Ecto.Entity`.

  ## Examples

      # The two following Model definitions are equivalent
      defmodule Post do
        use Ecto.Model

        queryable "posts" do
          field :text, :string
        end
      end

      defmodule Post do
        use Ecto.Model

        defmodule Entity do
          use Ecto.Entity, model: Post
          field :text, :string
        end

        queryable "posts", Entity
      end
  """
  defmacro queryable(name, opts // [], [do: block]) do
    quote do
      name = unquote(name)
      opts = unquote(opts)

      defmodule Entity do
        use Ecto.Entity, Keyword.put(opts, :model, unquote(__CALLER__.module))
        unquote(block)
      end

      queryable(name, Entity)
    end
  end
end
