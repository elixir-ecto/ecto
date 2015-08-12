defmodule Ecto.Type do
  @moduledoc """
  Defines functions and the `Ecto.Type` behaviour for implementing
  custom types.

  A custom type expects 4 functions to be implemented, all documented
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
        @behaviour Ecto.Type
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

        @primary_key {:id, Permalink, autogenerate: true}
        schema "posts" do
          ...
        end
      end

  ## New types

  In the previous example, we say we were augmenting an existing type
  because we were keeping the underlying representation the same, the
  value stored in the struct and the database was always an integer.

  Ecto types also allow developers to create completely new types as
  long as they can be encoded by the database. `Ecto.DateTime` and
  `Ecto.UUID` are such examples.
  """

  import Kernel, except: [match?: 2]

  use Behaviour

  @type t         :: primitive | custom
  @type primitive :: base | composite
  @type custom    :: atom

  @typep base      :: :integer | :float | :boolean | :string | :map |
                      :binary | :decimal | :id | :binary_id | :any
  @typep composite :: {:array, base} | {:embed, Ecto.Embedded.t}

  @base      ~w(integer float boolean string binary decimal id binary_id map any)a
  @composite ~w(array embed)a

  @doc """
  Returns the underlying schema type for the custom type.

  For example, if you want to provide your own datetime
  structures, the type function should return `:datetime`.
  """
  defcallback type :: t

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
  def primitive?(base) when base in @base, do: true
  def primitive?(_), do: false

  @doc """
  Checks if the given atom can be used as composite type.

      iex> composite?(:array)
      true
      iex> composite?(:string)
      false

  """
  @spec composite?(atom) :: boolean
  def composite?(atom), do: atom in @composite

  @doc """
  Checks if the given atom can be used as base type.

      iex> base?(:string)
      true
      iex> base?(:array)
      false
      iex> base?(Custom)
      false

  """
  @spec base?(atom) :: boolean
  def base?(atom), do: atom in @base

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
  Checks if a given type matches with a primitive type
  that can be found in queries.

      iex> match?(:string, :any)
      true
      iex> match?(:any, :string)
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
  def match?(schema_type, query_type) do
    if primitive?(schema_type) do
      do_match?(schema_type, query_type)
    else
      do_match?(schema_type.type, query_type)
    end
  end

  defp do_match?(_left, :any),  do: true
  defp do_match?(:any, _right), do: true
  defp do_match?({outer, left}, {outer, right}), do: match?(left, right)
  defp do_match?({:array, :any}, {:embed, %{cardinality: :many}}), do: true
  defp do_match?(:decimal, type) when type in [:float, :integer], do: true
  defp do_match?(:binary_id, :binary), do: true
  defp do_match?(:id, :integer), do: true
  defp do_match?(type, type), do: true
  defp do_match?(_, _), do: false

  @doc """
  Dumps a value to the given type.

  Opposite to casting, dumping requires the returned value
  to be a valid Ecto type, as it will be sent to the
  underlying data store.

      iex> dump(:string, nil)
      {:ok, %Ecto.Query.Tagged{value: nil, type: :string}}
      iex> dump(:string, "foo")
      {:ok, "foo"}

      iex> dump(:integer, 1)
      {:ok, 1}
      iex> dump(:integer, "10")
      :error

      iex> dump(:binary, "foo")
      {:ok, %Ecto.Query.Tagged{value: "foo", type: :binary}}
      iex> dump(:binary, 1)
      :error

      iex> dump({:array, :integer}, [1, 2, 3])
      {:ok, [1, 2, 3]}
      iex> dump({:array, :integer}, [1, "2", 3])
      :error
      iex> dump({:array, :binary}, ["1", "2", "3"])
      {:ok, %Ecto.Query.Tagged{value: ["1", "2", "3"], type: {:array, :binary}}}

  A `dumper` function may be given for handling recursive types.
  """
  @spec dump(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def dump(type, value, dumper \\ &dump/2)

  def dump({:embed, embed}, value, dumper) do
    dump_embed(embed, value, dumper)
  end

  def dump(type, nil, _dumper) do
    {:ok, %Ecto.Query.Tagged{value: nil, type: type(type)}}
  end

  def dump({:array, type}, value, dumper) do
    if is_list(value) do
      dump_array(type, value, dumper, [], false)
    else
      :error
    end
  end

  def dump(type, value, _dumper) do
    cond do
      not primitive?(type) ->
        type.dump(value)
      of_base_type?(type, value) ->
        {:ok, tag(type, value)}
      true ->
        :error
    end
  end

  defp tag(:binary, value),
    do: %Ecto.Query.Tagged{type: :binary, value: value}
  defp tag(_type, value),
    do: value

  defp dump_array(type, [h|t], dumper, acc, tagged) do
    case dumper.(type, h) do
      {:ok, %Ecto.Query.Tagged{value: h}} ->
        dump_array(type, t, dumper, [h|acc], true)
      {:ok, h} ->
        dump_array(type, t, dumper, [h|acc], tagged)
      :error ->
        :error
    end
  end

  defp dump_array(type, [], _dumper, acc, true) do
    {:ok, %Ecto.Query.Tagged{value: Enum.reverse(acc), type: type({:array, type})}}
  end

  defp dump_array(_type, [], _dumper, acc, false) do
    {:ok, Enum.reverse(acc)}
  end

  defp dump_embed(%{cardinality: :one} = embed, nil, _fun) do
    {:ok, %Ecto.Query.Tagged{value: nil, type: type({:embed, embed})}}
  end

  defp dump_embed(%{cardinality: :one, related: model, field: field} = embed,
                  value, fun) when is_map(value) do
    assert_replace_strategy!(embed)
    {:ok, dump_embed(field, model, value, model.__schema__(:types), fun)}
  end

  defp dump_embed(%{cardinality: :many, related: model, field: field} = embed,
                  value, fun) when is_list(value) do
    assert_replace_strategy!(embed)
    types = model.__schema__(:types)
    {:ok, for(changeset <- value,
              model = dump_embed(field, model, changeset, types, fun),
              do: model)}
  end

  defp dump_embed(_embed, _value, _fun) do
    :error
  end

  defp dump_embed(_field, _model, %Ecto.Changeset{action: :delete}, _types, _fun) do
    nil
  end

  defp dump_embed(_field, model, %Ecto.Changeset{model: %{__struct__: model}} = changeset, types, dumper) do
    %{model: struct, changes: changes} = changeset

    Enum.reduce(types, %{}, fn {field, type}, acc ->
      value =
        case Map.fetch(changes, field) do
          {:ok, change} -> change
          :error        -> Map.get(struct, field)
        end

      case dumper.(type, value) do
        {:ok, value} -> Map.put(acc, field, value)
        :error       -> raise ArgumentError, "cannot dump `#{inspect value}` as type #{inspect type}"
      end
    end)
  end

  defp dump_embed(field, _model, value, _types, _fun) do
    raise ArgumentError, "cannot dump embed `#{field}`, invalid value: #{inspect value}"
  end

  @doc """
  Loads a value with the given type.

      iex> load(:string, nil)
      {:ok, nil}
      iex> load(:string, "foo")
      {:ok, "foo"}

      iex> load(:integer, 1)
      {:ok, 1}
      iex> load(:integer, "10")
      :error

  A `loader` function may be given for handling recursive types.
  """
  @spec load(t, term, (t, term -> {:ok, term} | :error)) :: {:ok, term} | :error
  def load(type, value, loader \\ &load/2)

  def load({:embed, embed}, value, loader) do
    load_embed(embed, value, loader)
  end

  def load(_type, nil, _loader), do: {:ok, nil}

  def load({:array, type}, value, loader) do
    if is_list(value) do
      array(value, &loader.(type, &1), [])
    else
      :error
    end
  end

  def load(type, value, _loader) do
    cond do
      not primitive?(type) ->
        type.load(value)
      of_base_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

  defp load_embed(%{cardinality: :one}, nil, _fun), do: {:ok, nil}

  defp load_embed(%{cardinality: :one, related: model, field: field} = embed,
                  value, fun) when is_map(value) do
    assert_replace_strategy!(embed)
    {:ok, load_embed(field, model, value, fun)}
  end

  defp load_embed(%{cardinality: :many}, nil, _fun), do: {:ok, []}

  defp load_embed(%{cardinality: :many, related: model, field: field} = embed,
                  value, fun) when is_list(value) do
    assert_replace_strategy!(embed)
    {:ok, Enum.map(value, &load_embed(field, model, &1, fun))}
  end

  defp load_embed(_embed, _value, _fun) do
    :error
  end

  defp load_embed(_field, model, value, loader) when is_map(value) do
    Ecto.Schema.__load__(model, nil, nil, nil, value, loader)
  end

  defp load_embed(field, _model, value, _fun) do
    raise ArgumentError, "cannot load embed `#{field}`, invalid value: #{inspect value}"
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

      iex> cast(:id, 1)
      {:ok, 1}
      iex> cast(:id, "1")
      {:ok, 1}
      iex> cast(:id, "1.0")
      :error

      iex> cast(:float, 1.0)
      {:ok, 1.0}
      iex> cast(:float, 1)
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
  def cast({:embed, _}, _) do
    :error
  end

  def cast(_type, nil), do: {:ok, nil}

  def cast({:array, type}, term) do
    if is_list(term) do
      array(term, &cast(type, &1), [])
    else
      :error
    end
  end

  def cast(:binary_id, term) do
    if is_binary(term) do
      {:ok, term}
    else
      :error
    end
  end

  def cast(:float, term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _           -> :error
    end
  end
  def cast(:float, term) when is_integer(term), do: {:ok, term + 0.0}

  def cast(:boolean, term) when term in ~w(true 1),  do: {:ok, true}
  def cast(:boolean, term) when term in ~w(false 0), do: {:ok, false}

  def cast(:decimal, term) when is_binary(term) or is_number(term) do
    {:ok, Decimal.new(term)} # TODO: Add Decimal.parse/1
  rescue
    Decimal.Error -> :error
  end

  def cast(type, term) when type in [:id, :integer] and is_binary(term) do
    case Integer.parse(term) do
      {int, ""} -> {:ok, int}
      _         -> :error
    end
  end

  def cast(type, value) do
    cond do
      not primitive?(type) ->
        type.cast(value)
      of_base_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

  ## Helpers

  # Checks if a value is of the given primitive type.
  defp of_base_type?(:any, _),        do: true
  defp of_base_type?(:id, term),      do: is_integer(term)
  defp of_base_type?(:float, term),   do: is_float(term)
  defp of_base_type?(:integer, term), do: is_integer(term)
  defp of_base_type?(:boolean, term), do: is_boolean(term)

  defp of_base_type?(:binary, term), do: is_binary(term)
  defp of_base_type?(:string, term), do: is_binary(term)
  defp of_base_type?(:map, term),    do: is_map(term) and not Map.has_key?(term, :__struct__)

  defp of_base_type?(:decimal, %Decimal{}), do: true
  defp of_base_type?(:binary_id, value) do
    raise "cannot dump/load :binary_id type directly, attempted value: #{inspect value}"
  end

  defp of_base_type?(struct, _) when struct in ~w(decimal date time datetime)a, do: false

  defp array([h|t], fun, acc) do
    case fun.(h) do
      {:ok, h} -> array(t, fun, [h|acc])
      :error   -> :error
    end
  end

  defp array([], _fun, acc) do
    {:ok, Enum.reverse(acc)}
  end

  defp assert_replace_strategy!(%{strategy: :replace}), do: :ok
  defp assert_replace_strategy!(%{strategy: strategy, field: field}) do
    raise ArgumentError, "could not load/dump embed `#{field}` because the current adapter " <>
                         "does not support strategy `#{strategy}`"
  end
end
