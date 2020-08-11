defmodule Ecto.ParameterizedType do
  @moduledoc """
  Parameterized types are Ecto types that can be customized per field.

  Paramterized types allow a set of options to be specified in the schema
  which are initialized on compilation and passed to the callback functions
  as the last argument. 

  For example, `field :foo, :string` behaves the same for every field.
  On the other hand, `field :foo, Ecto.Enum, values: [:foo, :bar, :baz]`
  will likely have a different set of values per field.

  Note that options are specified as a keyword, but it is idiomatic to
  convert them to maps inside `c:init/1` for easier pattern matching in
  other callbacks.

  Parameterized types are a superset of regular types. In other words,
  with parameterized types you can do everything a regular type does,
  and more. For example, parameterized types can handle `nil` values
  in both `load` and `dump` callbacks, they can customize `cast` behavior
  per query and per changeset, and also control how values are embedded.
  
  However, parameterized types are also more complex. Therefore, if
  everything you need to achieve can be done with basic types, they
  should be preferred to parameterized ones.

  ## Examples

  To create a parameterized type, create a module as shown below:

    defmodule MyApp.MyType do
        use Ecto.ParameterizedType

        def type(_params), do: :string

        def init(opts) do
          validate_opts(opts)
          Enum.into(opts, %{})
        end

        def cast(data, params) do
          ...
          cast_data
        end

        def load(data, _loader, params) do
          ...
          {:ok, loaded_data}
        end

        def dump(data, dumper, params) do
          ...
          {:ok, dumped_data}
        end

        def equal?(a, b, _params) do
          a == b
        end
      end

  To use this type in a schema field, specify the type and parameters like this:

      schema "foo" do
        field :bar, MyApp.MyType, opt1: :baz, opt2: :boo
      end

  """

  @type opts :: keyword()

  @type params :: term()

  @callback init(opts :: opts()) :: params()

  @callback cast(data :: term, params :: params()) ::
              {:ok, term} | {:error, keyword()} | :error

  @callback load(value :: any(), loader :: function(), params :: params()) :: {:ok, value :: any()} | :error

  @callback dump(value :: any(), dumper :: function(), params :: params()) :: {:ok, value :: any()} | :error

  @callback type(params :: params()) :: Ecto.Type.t()

  @callback equal?(value1 :: any(), value2 :: any(), params :: params()) :: boolean()

  @callback embed_as(format :: atom(), params :: params()) :: :self | :dump

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Ecto.ParameterizedType
      # TODO: Make both equal? and embed_as specific only to parameterized types
      def embed_as(_, _), do: :self
      # TODO: evaluate if we should keep this once we add cast/3 and change/3
      def equal?(term1, term2, _params), do: term1 == term2
      defoverridable embed_as: 2, equal?: 3
    end
  end
end
