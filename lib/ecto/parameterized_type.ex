defmodule Ecto.ParameterizedType do
  @moduledoc """
  Parameterized types are similar to Ecto Custom Types, however they allow a set of options to be
  specified in the schema which are initialized on compilation and passed to the cast, load, dump,
  and type functions as a second argument.

  ## Examples

    To create a parameterized type, create a module like this:

    defmodule MyApp.MyType do
      use Ecto.ParameterizedType

      def type(_opts), do: :string

      def init(opts) do
        ...
        opts
      end

      def cast(data, current, opts) do
        ...
        cast_data
      end

      def load(data, opts) do
        ...
        {:ok, loaded_data}
      end

      def dump(data, opts) do
        ...
        {:ok, dumped_data}
      end

      def equal?(a, b, _opts) do
        a == b
      end
    end

  To use this type in a schema field, specify it in the form {module, keyword_opts} like this:

    schema "foo" do
      field "bar", {MyApp.MyType, opt1: :baz, opt2: :boo}
    end

  """

  @type opts :: keyword() | map()

  @callback init(opts :: keyword()) :: opts()

  @callback cast(data :: term, current :: term, opts :: opts()) :: {:ok, term} | {:error, keyword()} | :error

  @callback load(term, opts :: opts()) :: {:ok, term} | :error

  @callback dump(term, opts :: opts()) :: {:ok, term} | :error

  @callback dump(term, dumper :: any(), opts :: opts()) :: {:ok, term} | :error

  @callback type(opts :: opts()) :: Ecto.Type.t()

  @callback equal?(term, term, opts :: opts()) :: boolean()

  @callback embed_as(format :: atom, opts :: opts()) :: :self | :dump

  @callback apply_changes(value :: any(), opts :: opts()) :: any()

  @callback missing?(value :: any(), opts :: opts()) :: boolean

  @callback empty(opts :: opts()) :: any()

  @callback match?(other :: any(), opts :: opts()) :: boolean

  @callback change(value :: any(), current :: any(), opts :: opts()) :: any()

  @callback validate_json_path!(list(String.t()), String.t(), opts()) :: :ok | no_return

  @doc false
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Ecto.ParameterizedType
      def embed_as(_, _), do: :self
      def equal?(term1, term2, _opts), do: term1 == term2
      def missing?(value, _opts), do: is_nil(value)
      def empty(_opts), do: nil
      defoverridable [embed_as: 2, equal?: 3, missing?: 2, empty: 1]
    end
  end
end
