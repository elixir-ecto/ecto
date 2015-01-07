defmodule Ecto.Type do
  @moduledoc """
  Defines the `Ecto.Type` behaviour for implementing custom types.

  A custom type expects 4 functions to be implemented, all documented
  and described below. We also provide two examples of how custom
  types can be used in Ecto to augment existing types or providing
  your own types.

  Through this documentation we refer to "Ecto native types". Those
  are the types described in the `Ecto.Model.Schema` documentation.

  ## Augmenting types

  Imagine you want to support your id field to be looked up as a
  permalink. For example, you want the following query to work:

      permalink = "10-how-to-be-productive-with-elixir"
      from p in Post, where: p.id == ^permalink

  If `id` is an integer field, Ecto will fail in the query above
  because it cannot cast the string to an integer. By using a
  custom type, we can provide special casting behaviour while
  still keeping the underlying Ecto type the same:

      defmodule Permalink do
        def type, do: :integer

        # Provide our own casting rules.
        def cast(string) when is_binary(string) do
          case Integer.parse(string) do
            {int, _} -> {:ok, int}
            :error   -> :error
          end
        end

        # We should still accept integers
        def cast(integer) when is_integer(integer), do: {:ok, integer}

        # Everything else is a failure though
        def cast(_), do: :error

        # When loading data from the database, we are guaranteed to
        # receive an integer (as database are stricts) and we will
        # just return it to be stored in the model struct.
        def load(integer) when is_integer(integer), do: {:ok, integer}

        # When dumping data to the database, we *expect* an integer
        # but any value could be inserted into the struct, so we need
        # guard against them.
        def dump(integer) when is_integer(integer), do: {:ok, integer}
        def dump(_), do: :error
      end

  Now, we can use our new field above as our primary key type in models:

      defmodule Post do
        use Ecto.Model

        @primary_key {:id, Permalink, []}
        schema "posts" do
          ...
        end
      end

  ## New types

  In the previous example, we say we were augmenting an existing type
  because we were keeping the underlying representation the same, the
  value stored in the struct and the database was always an integer.

  However, sometimes, we want to completely replace Ecto data types
  stored in the models. For example, data intensive applications may
  find the `%Ecto.Datetime{}` struct, used by `:datetime` columns, too
  simple and wish to use a more robust alternative.

  This can be achieved by implementing the proper `load/1` and `dump/1`
  functions:

      defmodule SuperDateTime do
        defstruct [:year, :month, :day, :hour, :min, :sec]

        def type, do: :datetime

        # Provide our own casting rules.
        def cast(string) when is_binary(string) do
          # Here, for example, you could try to parse different string formats.
        end

        # Our custom datetime should also be valid
        def cast(%SuperDateTime{} = datetime) do
          {:ok, datetime}
        end

        # Everything else needs to be a failure though
        def cast(_), do: :error

        # When loading data from the database, we need to convert
        # the Ecto type (Ecto.DateTime in this case) to our type:
        def load(%Ecto.DateTime{} = dt) do
          {:ok, %SuperDateTime{year: dt.year, month: dt.month, day: dt.day,
                               hour: dt.hour, min: dt.min, sec: dt.sec}}
        end

        # When dumping data to the database, we need to convert
        # our type back to Ecto.DateTime one:
        def dump(%SuperDateTime{} = dt) do
          {:ok, %Ecto.DateTime{year: dt.year, month: dt.month, day: dt.day,
                               hour: dt.hour, min: dt.min, sec: dt.sec}}
        end
        def dump(_), do: :error
      end

  Now we can use in our fields too:

      field :published_at, SuperDateTime

  And that is all. By defining a custom type, we were able to extend Ecto's
  casting abilities and also any Elixir value in our models while preserving
  Ecto guarantees to safety and type conversion.
  """

  use Behaviour

  @doc """
  Returns the underlying schema type for the custom type.

  For example, if you want to provide your own datetime
  structures, the type function should return `:datetime`.
  """
  defcallback type :: atom | {atom, atom}

  @doc """
  Casts the given input to the custom type.

  This callback is called on external input and can return any type,
  as long as the `dump/1` function is able to convert the returned
  value back into an Ecto native type. There are two situations where
  this callback is called:

    1. When casting values by `Ecto.Changeset`
    2. When passing arguments to `Ecto.Query`

  """
  defcallback cast(term) :: term

  @doc """
  Loads the given term into a custom type.

  This callback is called when loading data from the database and
  receive an Ecto native type. It can return any type, as long as
  the `dump/1` function is able to convert the returned value back
  into an Ecto native type.
  """
  defcallback load(term) :: term

  @doc """
  Dumps the given term into an Ecto native type.

  This callback is called with any term that was stored in the struct
  and it needs to validate them and convert it to an Ecto native type.
  """
  defcallback dump(term) :: term
end
