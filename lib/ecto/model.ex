defmodule Ecto.Model do
  defmacro __using__(_opts) do
    quote do
      import Ecto.Model.Queryable
    end
  end
end

defmodule Ecto.Model.Queryable do
  defmacro queryable(name, [do: _] = block) do
    quote do
      queryable(unquote(name), :id, unquote(block))
    end
  end

  defmacro queryable(name, entity) do
    quote bind_quoted: [name: name, entity: entity] do
      def new(params) do
        unquote(entity).new(params)
      end
      def __ecto__(:name), do: unquote(name)
      def __ecto__(:entity), do: unquote(entity)
    end
  end

  defmacro queryable(name, primary_key, [do: block]) do
    quote do
      name = unquote(name)

      defmodule Entity do
        use Ecto.Entity
        @ecto_model unquote(__CALLER__.module)
        dataset unquote(primary_key) do
          unquote(block)
        end
      end

      queryable(name, Entity)
    end
  end
end
