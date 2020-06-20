defmodule Ecto.Type.Atom do
  @moduledoc """
  Ecto.Type.Atom provides the ability to store atoms using the underlying :string ecto type. This
  is done in a manner that is safe with respect to atom overflow as only specified existing atoms
  can be loaded.

  ## Examples

    To define a game schema with status as an atom field:

      defmodule MyApp.Games.Game do
        use MyApp.Schema

        # First define the Status atom type:
        defmodule Status do
          use Ecto.Type.Atom, values: [:joining, :running, :ended]
        end

        schema "games" do
          ...
          # Then use the Status module as the field type:
          field :status, Status
          ...
        end
      end

  A helper function `values/0` is generated on the module, e.g. `Status.values()` with the above module
  will return [:joining, :running, :ended]

  An `else` option is provided to handle cases where the value being loaded is not in the specified
  values. There are three valid values for the `else` option:

    `:error` - (default if no `else` specified) returns `:error` to the ecto load request, causing it to fail.
    `{:ok, value}` - returns the specified value to the ecto load request.
    `:transform` - calls `transform/1` on the module, giving the value being loaded. The transform
                function should return `:error` or `{:ok, value}`.

  Note that for `{:ok, value}` in both of the second two options above, the value returned
  in `{:ok, value}` does *not* need to be one of the specified values. This allows you to
  return a different value, which can be cleaned up after loading, but won't be allowed to
  be stored back to the database. This can be useful in cases where you want to handle bad
  or deprecated values in your application code after loading.

  ## Example else usage

    If we wanted to return a set value like :unknown when values other than those specified are
    loaded, we use `else: {:ok, :unknown}`:

      defmodule Status do
        use Ecto.Type.Atom, values: [:joining, :running, :ended], else: {:ok, :unknown}
      end

    And if we wanted to transform any non-specified values when loaded, we use `else: :transform`,
    and then specify a `transform/1` function in the module.

      defmodule Status do
        use Ecto.Type.Atom, values: [:joining, :running, :ended], else: :transform

        def transform("legacy value 1"), do: {:ok, :new_value_1}
        def transform("legacy value 2"), do: {:ok, :new_value_2}
        def transform(_), do: :errors
      end

    Note that if you do not specify a `transform/1` returning both `:error` and `{:ok, value}`, you will get a
    dialyzer warning.

  """
  defmacro __using__(opts) do
    values_as_atoms = Keyword.fetch!(opts, :values)
    Enum.each(values_as_atoms, fn val -> if !is_atom(val), do: raise("values must be atoms") end)
    values_as_strings = Enum.map(values_as_atoms, &Atom.to_string/1)

    load_fun =
      case Keyword.get(opts, :else, :error) do
        :error ->
          quote do
            def load(_), do: :error
          end

        :transform ->
          quote do
            def load(data) do
              case __MODULE__.transform(data) do
                :error -> :error
                {:ok, return} -> {:ok, return}
              end
            end
          end

        {:ok, return_atom} when is_atom(return_atom) ->
          quote do
            def load(_), do: {:ok, unquote(return_atom)}
          end

        _ ->
          raise "`else` must be either :error, :transform, or {:ok, return_atom}"
      end

    quote do
      use Ecto.Type

      @values_as_atoms unquote(values_as_atoms)
      @values_as_strings unquote(values_as_strings)

      def type, do: :string

      def values, do: @values_as_atoms

      def cast(value) when value in @values_as_atoms, do: {:ok, value}
      def cast(value) when value in @values_as_strings, do: {:ok, String.to_existing_atom(value)}
      def cast(_), do: :error

      def load(data) when data in @values_as_strings, do: {:ok, String.to_existing_atom(data)}
      unquote(load_fun)

      def dump(value) when value in @values_as_atoms, do: {:ok, Atom.to_string(value)}
      def dump(_), do: :error
    end
  end
end
