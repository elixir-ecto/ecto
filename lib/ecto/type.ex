defmodule Ecto.Type do
  @moduledoc """
  Defines functions and the `Ecto.Type` behaviour for implementing
  custom types.

  A custom type expects 5 functions to be implemented, all documented
  and described below. We also provide two examples of how custom
  types can be used in Ecto to augment existing types or providing
  your own types.

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

        # Integers are never considered blank
        def blank?(_), do: false

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
  stored in the models. This is for example how Ecto provides the
  `Ecto.DateTime` struct as a replacement for the `:datetime` type.

  Check the `Ecto.DateTime` implementation for an example on how
  to implement such types.
  """

  import Kernel, except: [match?: 2]
  use Behaviour

  @type t         :: primitive | custom
  @type primitive :: basic | composite
  @type custom    :: atom

  @typep basic     :: :any | :integer | :float | :boolean | :string |
                      :binary | :uuid | :decimal | :datetime | :time | :date
  @typep composite :: {:array, basic}

  @basic     ~w(any integer float boolean string binary uuid decimal datetime time date)a
  @composite ~w(array)a

  @doc """
  Returns the underlying schema type for the custom type.

  For example, if you want to provide your own datetime
  structures, the type function should return `:datetime`.
  """
  defcallback type :: basic | custom

  @doc """
  Returns if the value is considered blank/empty for this type.

  This function is called by `Ecto.Changeset` after the value
  has been `cast/1`, therefore it receives the values returned
  by `cast/1`.
  """
  defcallback blank?(term) :: boolean

  @doc """
  Casts the given input to the custom type.

  This callback is called on external input and can return any type,
  as long as the `dump/1` function is able to convert the returned
  value back into an Ecto native type. There are two situations where
  this callback is called:

    1. When casting values by `Ecto.Changeset`
    2. When passing arguments to `Ecto.Query`

  """
  defcallback cast(term) :: {:ok, term} | :error

  @doc """
  Loads the given term into a custom type.

  This callback is called when loading data from the database and
  receive an Ecto native type. It can return any type, as long as
  the `dump/1` function is able to convert the returned value back
  into an Ecto native type.
  """
  defcallback load(term) :: {:ok, term} | :error

  @doc """
  Dumps the given term into an Ecto native type.

  This callback is called with any term that was stored in the struct
  and it needs to validate them and convert it to an Ecto native type.
  """
  defcallback dump(term) :: {:ok, term} | :error

  ## Functions

  @doc """
  Checks if we have a primitive type.

      iex> primitive?(:string)
      true
      iex> primitive?(Another)
      false

      iex> primitive?({:array, :string})
      true
      iex> primitive?({:array, Another})
      true

  """
  @spec primitive?(t) :: boolean
  def primitive?({composite, _}) when composite in @composite, do: true
  def primitive?(basic) when basic in @basic, do: true
  def primitive?(_), do: false

  @doc """
  Retrieves the underlying type of a given type.

      iex> type(:string)
      :string
      iex> type(Ecto.DateTime)
      :datetime

      iex> type({:array, :string})
      {:array, :string}
      iex> type({:array, Ecto.DateTime})
      {:array, :datetime}

  """
  @spec type(t) :: t
  def type(type)

  def type({:array, type}), do: {:array, type(type)}

  def type(type) do
    if primitive?(type) do
      type
    else
      type.type
    end
  end

  @doc """
  Checks if a given type matches with a primitive type.

      iex> match?(:whatever, :any)
      true
      iex> match?(:any, :whatever)
      true
      iex> match?(:string, :string)
      true

      iex> match?({:array, :string}, {:array, :any})
      true

      iex> match?(Ecto.DateTime, :datetime)
      true
      iex> match?(Ecto.DateTime, :string)
      false

  """
  @spec match?(t, primitive) :: boolean
  def match?(_left, :any),  do: true
  def match?(:any, _right), do: true

  def match?(type, primitive) do
    if primitive?(type) do
      do_match?(type, primitive)
    else
      do_match?(type.type, primitive)
    end
  end

  defp do_match?({outer, left}, {outer, right}), do: match?(left, right)
  defp do_match?(type, type),                    do: true
  defp do_match?(_, _),                          do: false

  @doc """
  Dumps a value to the given type.

  Opposite to casting, dumping requires the returned value
  to be a valid Ecto type, as it will be sent to the
  underlying data store.

      iex> dump(:string, nil)
      {:ok, nil}
      iex> dump(:string, "foo")
      {:ok, "foo"}

      iex> dump(:integer, 1)
      {:ok, 1}
      iex> dump(:integer, "10")
      :error

  """
  @spec dump(t, term) :: {:ok, term} | :error
  def dump(_type, nil), do: {:ok, nil}

  def dump({:array, type}, value) do
    array(type, value, &dump/2, [])
  end

  def dump(type, value) do
    cond do
      not primitive?(type) ->
        type.dump(value)
      of_basic_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

  @doc """
  Same as `dump/2` but raises if value can't be dumped.
  """
  @spec dump!(t, term) :: term | no_return
  def dump!(type, term) do
    case dump(type, term) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot dump `#{inspect term}` to type #{inspect type}"
    end
  end

  @doc """
  Loads a value with the given type.

  Load is invoked when loading database native types
  into a struct.

      iex> load(:string, nil)
      {:ok, nil}
      iex> load(:string, "foo")
      {:ok, "foo"}

      iex> load(:integer, 1)
      {:ok, 1}
      iex> load(:integer, "10")
      :error
  """
  @spec load(t, term) :: {:ok, term} | :error
  def load(_type, nil), do: {:ok, nil}

  def load({:array, type}, value) do
    array(type, value, &load/2, [])
  end

  def load(type, value) do
    cond do
      not primitive?(type) ->
        type.load(value)
      of_basic_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

  @doc """
  Same as `load/2` but raises if value can't be loaded.
  """
  @spec load!(t, term) :: term | no_return
  def load!(type, term) do
    case load(type, term) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot load `#{inspect term}` as type #{inspect type}"
    end
  end

  @doc """
  Casts a value to the given type.

  `cast/2` is used by the finder queries and changesets
  to cast outside values to specific types.

  Note that nil can be cast to all primitive types as data
  stores allow nil to be set on any column. Custom data types
  may want to handle nil specially though.

      iex> cast(:any, "whatever")
      {:ok, "whatever"}

      iex> cast(:any, nil)
      {:ok, nil}
      iex> cast(:string, nil)
      {:ok, nil}

      iex> cast(:integer, 1)
      {:ok, 1}
      iex> cast(:integer, "1")
      {:ok, 1}
      iex> cast(:integer, "1.0")
      :error

      iex> cast(:float, 1.0)
      {:ok, 1.0}
      iex> cast(:float, "1")
      {:ok, 1.0}
      iex> cast(:float, "1.0")
      {:ok, 1.0}
      iex> cast(:float, "1-foo")
      :error

      iex> cast(:boolean, true)
      {:ok, true}
      iex> cast(:boolean, false)
      {:ok, false}
      iex> cast(:boolean, "1")
      {:ok, true}
      iex> cast(:boolean, "0")
      {:ok, false}
      iex> cast(:boolean, "whatever")
      :error

      iex> cast(:string, "beef")
      {:ok, "beef"}
      iex> cast(:uuid, "beef")
      {:ok, "beef"}
      iex> cast(:binary, "beef")
      {:ok, "beef"}

      iex> cast(:decimal, Decimal.new(1.0))
      {:ok, Decimal.new(1.0)}
      iex> cast(:decimal, Decimal.new("1.0"))
      {:ok, Decimal.new(1.0)}

      iex> cast({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :integer}, ["1", "2", "3"])
      {:ok, [1, 2, 3]}
      iex> cast({:array, :string}, [1, 2, 3])
      :error
      iex> cast(:string, [1, 2, 3])
      :error

  """
  @spec cast(t, term) :: {:ok, term} | :error
  def cast(_type, nil), do: {:ok, nil}

  def cast({:array, type}, value) do
    array(type, value, &cast/2, [])
  end

  def cast(type, value) do
    cond do
      not primitive?(type) ->
        type.cast(value)
      of_basic_type?(type, value) ->
        {:ok, value}
      true ->
        do_cast(type, value)
    end
  end

  defp do_cast(:integer, term) when is_binary(term) do
    case Integer.parse(term) do
      {int, ""} -> {:ok, int}
      _         -> :error
    end
  end

  defp do_cast(:float, term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _           -> :error
    end
  end

  defp do_cast(:boolean, term) when term in ~w(true 1),  do: {:ok, true}
  defp do_cast(:boolean, term) when term in ~w(false 0), do: {:ok, false}

  defp do_cast(:decimal, term) when is_binary(term) or is_number(term) do
    {:ok, Decimal.new(term)} # TODO: Add Decimal.parse/1
  rescue
    Decimal.Error -> :error
  end

  defp do_cast(_, _), do: :error

  @doc """
  Same as `cast/2` but raises if value can't be cast.
  """
  @spec cast!(t, term) :: term | no_return
  def cast!(type, term) do
    case cast(type, term) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot cast `#{inspect term}` to type #{inspect type}"
    end
  end

  @doc """
  Checks if an already cast value is blank.

  This is used by `Ecto.Changeset.cast/4` when casting required fields.

      iex> blank?(:string, nil)
      true
      iex> blank?(:integer, nil)
      true

      iex> blank?(:string, "")
      true
      iex> blank?(:string, "  ")
      true
      iex> blank?(:string, "hello")
      false

      iex> blank?({:array, :integer}, [])
      true
      iex> blank?({:array, :integer}, [1, 2, 3])
      false

      iex> blank?({:array, Whatever}, [])
      true
      iex> blank?({:array, Whatever}, [1, 2, 3])
      false

  """
  @spec blank?(t, term) :: boolean
  def blank?(_type, nil), do: true

  def blank?({:array, _}, value), do: value == []

  def blank?(type, value) do
    if primitive?(type) do
      blank?(value)
    else
      type.blank?(value)
    end
  end

  @doc ~S"""
  Checks if a value is blank.

  This is an implementation that can be used by custom types,
  typically tupes that are attempting to cast values from
  strings.

  Strings made only of spaces are considered blank.

      iex> blank?("")
      true
      iex> blank?("foo")
      false
      iex> blank?("   ")
      true
      iex> blank?("\t")
      true

  """
  def blank?(""), do: true
  def blank?(string) when is_binary(string), do: String.lstrip(string) == ""
  def blank?(_), do: false

  ## Helpers

  # Checks if a value is of the given primitive type.
  defp of_basic_type?(:any, _), do: true
  defp of_basic_type?(:float, term),   do: is_float(term)
  defp of_basic_type?(:integer, term), do: is_integer(term)
  defp of_basic_type?(:boolean, term), do: is_boolean(term)

  defp of_basic_type?(binary, term) when binary in ~w(binary uuid string)a, do: is_binary(term)

  defp of_basic_type?(:decimal, %Decimal{}), do: true
  defp of_basic_type?(:date, {_, _, _}),  do: true
  defp of_basic_type?(:time, {_, _, _}),  do: true
  defp of_basic_type?(:datetime, {{_, _, _}, {_, _, _}}), do: true
  defp of_basic_type?(struct, _) when struct in ~w(decimal date time datetime)a, do: false

  defp array(type, [h|t], fun, acc) do
    case fun.(type, h) do
      {:ok, h} -> array(type, t, fun, [h|acc])
      :error   -> :error
    end
  end

  defp array(_type, [], _fun, acc) do
    {:ok, Enum.reverse(acc)}
  end
end
