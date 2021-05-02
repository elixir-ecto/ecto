defmodule Ecto.ParameterizedType do
  @moduledoc """
  Parameterized types are Ecto types that can be customized per field.

  Parameterized types allow a set of options to be specified in the schema
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

  @typedoc """
  The keyword options passed from the Schema's field macro into `c:init/1`
  """
  @type opts :: keyword()

  @typedoc """
  The parameters for the ParameterizedType

  This is the value passed back from `c:init/1` and subsequently passed
  as the last argument to all callbacks. Idiomatically it is a map.
  """
  @type params :: term()

  @doc """
  Callback to convert the options specified in  the field macro into parameters
  to be used in other callbacks.

  This function is called at compile time, and should raise if invalid values are
  specified. It is idiomatic that the parameters returned from this are a map.
  `field` and `schema` will be injected into the options automatically.

  For example, this schema specification

      schema "my_table" do
        field :my_field, MyParameterizedType, opt1: :foo, opt2: nil
      end

  will result in the call:

      MyParameterizedType.init([schema: "my_table", field: :my_field, opt1: :foo, opt2: nil])

  """
  @callback init(opts :: opts()) :: params()

  @doc """
  Casts the given input to the ParameterizedType with the given parameters.

  If the parameterized type is also a composite type,
  the inner type can be cast by calling `Ecto.Type.cast/2`
  directly.

  For more information on casting, see `c:Ecto.Type.cast/1`.
  """
  @callback cast(data :: term, params()) ::
              {:ok, term} | :error | {:error, keyword()}

  @doc """
  Loads the given term into a ParameterizedType.

  It receives a `loader` function in case the parameterized
  type is also a composite type. In order to load the inner
  type, the `loader` must be called with the inner type and
  the inner value as argument.

  For more information on loading, see `c:Ecto.Type.load/1`.
  Note that this callback *will* be called when loading a `nil`
  value, unlike `c:Ecto.Type.load/1`.
  """
  @callback load(value :: any(), loader :: function(), params()) :: {:ok, value :: any()} | :error

  @doc """
  Dumps the given term into an Ecto native type.

  It receives a `dumper` function in case the parameterized
  type is also a composite type. In order to dump the inner
  type, the `dumper` must be called with the inner type and
  the inner value as argument.

  For more information on dumping, see `c:Ecto.Type.dump/1`.
  Note that this callback *will* be called when dumping a `nil`
  value, unlike `c:Ecto.Type.dump/1`.
  """
  @callback dump(value :: any(), dumper :: function(), params()) :: {:ok, value :: any()} | :error

  @doc """
  Returns the underlying schema type for the ParameterizedType.

  For more information on schema types, see `c:Ecto.Type.type/0`
  """
  @callback type(params()) :: Ecto.Type.t()

  @doc """
  Checks if two terms are semantically equal.
  """
  @callback equal?(value1 :: any(), value2 :: any(), params()) :: boolean()

  @doc """
  Dictates how the type should be treated inside embeds.

  For more information on embedding, see `c:Ecto.Type.embed_as/1`
  """
  @callback embed_as(format :: atom(), params()) :: :self | :dump

  @doc """
  Generates a loaded version of the data.

  This is callback is invoked when a parameterized type is given
  to `field` with the `:autogenerate` flag.
  """
  @callback autogenerate(params()) :: term()

  @optional_callbacks autogenerate: 1

  @doc """
  Inits a parameterized type given by `type` with `opts`.

  Useful when manually initializing a type for schemaless changesets.
  """
  def init(type, opts) do
    {:parameterized, type, type.init(opts)}
  end

  @doc false
  defmacro __using__(_) do
    quote location: :keep do
      @behaviour Ecto.ParameterizedType

      @doc false
      def embed_as(_, _), do: :self

      @doc false
      def equal?(term1, term2, _params), do: term1 == term2

      defoverridable embed_as: 2, equal?: 3
    end
  end
end
