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
  defcallback type :: base | custom

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

  defp normalize({comp, :binary_id}, %{binary_id: binary_id}), do: {comp, binary_id}
  defp normalize(:binary_id, %{binary_id: binary_id}), do: binary_id
  defp normalize(:binary_id, %{}),
    do: raise "adapter did not provide a type for :binary_id"
  defp normalize({_comp, :binary_id}, %{}),
    do: raise "adapter did not provide a type for :binary_id"
  defp normalize(type, _id_types), do: type

  @doc """
  Checks if a given type matches with a primitive type
  that can be found in queries.

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
  def match?(schema_type, query_type)

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

      iex> dump(:string, nil, %{})
      {:ok, %Ecto.Query.Tagged{value: nil, type: :string}}
      iex> dump(:string, "foo", %{})
      {:ok, "foo"}

      iex> dump(:integer, 1, %{})
      {:ok, 1}
      iex> dump(:integer, "10", %{})
      :error

      iex> dump(:binary, "foo", %{})
      {:ok, %Ecto.Query.Tagged{value: "foo", type: :binary}}
      iex> dump(:binary, 1, %{})
      :error

      iex> dump({:array, :integer}, [1, 2, 3], %{})
      {:ok, [1, 2, 3]}
      iex> dump({:array, :integer}, [1, "2", 3], %{})
      :error
      iex> dump({:array, :binary}, ["1", "2", "3"], %{})
      {:ok, %Ecto.Query.Tagged{value: ["1", "2", "3"], type: {:array, :binary}}}

      iex> dump(:binary_id, "7d5bed50-e8ec-4a74-b863-eb977f3db92e", %{binary_id: Ecto.UUID})
      {:ok, %Ecto.Query.Tagged{tag: nil, type: :uuid,
        value: <<125, 91, 237, 80, 232, 236, 74, 116, 184, 99, 235, 151, 127, 61, 185, 46>>}}

  """
  @spec dump(t, term, map) :: {:ok, term} | :error
  def dump(type, nil, _id_types) do
    {:ok, %Ecto.Query.Tagged{value: nil, type: type(type)}}
  end

  def dump({:embed, embed}, value, id_types) do
    dump_embed(embed, value, id_types)
  end

  def dump(type, value, id_types) do
    dump(normalize(type, id_types), value)
  end

  defp dump(type, nil) do
    {:ok, %Ecto.Query.Tagged{value: nil, type: type(type)}}
  end

  defp dump({:array, type}, value) do
    if is_list(value) do
      dump_array(type, value, [], false)
    else
      :error
    end
  end

  defp dump(type, value) do
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

  defp dump_array(type, [h|t], acc, tagged) do
    case dump(type, h) do
      {:ok, %Ecto.Query.Tagged{value: h}} ->
        dump_array(type, t, [h|acc], true)
      {:ok, h} ->
        dump_array(type, t, [h|acc], tagged)
      :error ->
        :error
    end
  end

  defp dump_array(type, [], acc, true) do
    {:ok, %Ecto.Query.Tagged{value: Enum.reverse(acc), type: type({:array, type})}}
  end

  defp dump_array(_type, [], acc, false) do
    {:ok, Enum.reverse(acc)}
  end

  defp dump_embed(%{cardinality: :one, embed: model}, struct, id_types) do
    dump_model(model, struct, id_types)
  end

  defp dump_embed(%{cardinality: :many, container: :array, embed: model},
                  value, id_types) when is_list(value) do
    array(value, &dump_model(model, &1, id_types), [])
  end

  defp dump_embed(_embed, _value, _id_types) do
    :error
  end

  defp dump_model(model, %Ecto.Changeset{} = changeset, id_types) do
    dump_model(model, Ecto.Changeset.apply_changes(changeset), id_types)
  end

  defp dump_model(model, %{__struct__: model} = struct, id_types) do
    types = model.__schema__(:types)
    embeds = model.__schema__(:embeds)

    dumped =
      id_types.adapter.dump_embed(struct, model, types, id_types)

    dumped =
      Enum.reduce(embeds, dumped, fn field, acc ->
        {:embed, embed} = type = Map.get(types, field)
        case Map.get(field, acc) do
          nil   -> Map.put(acc, Ecto.Embedded.empty(embed))
          # TODO use dump! in stead of dump, and catch errors
          value -> dump!(type, value, id_types)
        end
      end)
    {:ok, dumped}
  end

  defp dump_model(_model, _struct, _id_types) do
    :error
  end

  @doc """
  Same as `dump/2` but raises if value can't be dumped.
  """
  @spec dump!(t, term, map) :: term | no_return
  def dump!(type, term, id_types) do
    case dump(type, term, id_types) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot dump `#{inspect term}` to type #{inspect type}"
    end
  end

  @doc """
  Loads a value with the given type.

  Load is invoked when loading database native types
  into a struct.

      iex> load(:string, nil, %{})
      {:ok, nil}
      iex> load(:string, "foo", %{})
      {:ok, "foo"}

      iex> load(:integer, 1, %{})
      {:ok, 1}
      iex> load(:integer, "10", %{})
      :error

      iex> load(:binary_id, <<125, 91, 237, 80, 232, 236, 74, 116, 184, 99, 235, 151, 127, 61, 185, 46>>, %{binary_id: Ecto.UUID})
      {:ok, "7d5bed50-e8ec-4a74-b863-eb977f3db92e"}

  """
  @spec load(t, term, map) :: {:ok, term} | :error
  def load({:embed, embed}, value, id_types) do
    load_embed(embed, value, id_types)
  end

  def load(type, value, id_types) do
    load(normalize(type, id_types), value)
  end

  defp load(_type, nil), do: {:ok, nil}

  defp load(:boolean, 0), do: {:ok, false}
  defp load(:boolean, 1), do: {:ok, true}

  defp load(:map, value) when is_binary(value) do
    {:ok, json_library.decode!(value)}
  end

  defp load({:array, type}, value) do
    if is_list(value) do
      array(value, &load(type, &1), [])
    else
      :error
    end
  end

  defp load(type, value) do
    cond do
      not primitive?(type) ->
        type.load(value)
      of_base_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

  defp load_embed(_embed, nil, _id_types), do: {:ok, nil}

  defp load_embed(%{cardinality: :one, embed: model}, value, id_types) do
    load_model(model, value, id_types)
  end

  defp load_embed(%{cardinality: :many, container: :array, embed: model}, value, id_types)
      when is_list(value) do
    array(value, &load_model(model, &1, id_types), [])
  end

  defp load_embed(_embed, _value, _id_types) do
    :error
  end

  defp load_model(model, value, id_types) when is_binary(value) do
    load_model(model, json_library.decode!(value), id_types)
  end

  defp load_model(model, value, id_types) when is_map(value) do
    types = model.__schema__(:types)
    embeds = model.__schema__(:embeds)

    loaded = id_types.adapter.load_embed(value, model, types, id_types)

    {:ok,
      Enum.reduce(embeds, struct(model, loaded), fn field, acc ->
        type = Map.get(types, field)
        # TODO use load instead of load! and catch errors
        Map.put(acc, field, load!(type, Map.get(acc, field), id_types))
      end)}
  end

  defp load_model(_model, _value, _id_types) do
    :error
  end

  defp json_library, do: Application.get_env(:ecto, :json_library)

  @doc """
  Same as `load/2` but raises if value can't be loaded.
  """
  @spec load!(t, term, map) :: term | no_return
  def load!(type, term, id_types) do
    case load(type, term, id_types) do
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

      iex> cast(:any, "whatever", %{})
      {:ok, "whatever"}

      iex> cast(:any, nil, %{})
      {:ok, nil}
      iex> cast(:string, nil, %{})
      {:ok, nil}

      iex> cast(:integer, 1, %{})
      {:ok, 1}
      iex> cast(:integer, "1", %{})
      {:ok, 1}
      iex> cast(:integer, "1.0", %{})
      :error

      iex> cast(:id, 1, %{})
      {:ok, 1}
      iex> cast(:id, "1", %{})
      {:ok, 1}
      iex> cast(:id, "1.0", %{})
      :error

      iex> cast(:float, 1.0, %{})
      {:ok, 1.0}
      iex> cast(:float, 1, %{})
      {:ok, 1.0}
      iex> cast(:float, "1", %{})
      {:ok, 1.0}
      iex> cast(:float, "1.0", %{})
      {:ok, 1.0}
      iex> cast(:float, "1-foo", %{})
      :error

      iex> cast(:boolean, true, %{})
      {:ok, true}
      iex> cast(:boolean, false, %{})
      {:ok, false}
      iex> cast(:boolean, "1", %{})
      {:ok, true}
      iex> cast(:boolean, "0", %{})
      {:ok, false}
      iex> cast(:boolean, "whatever", %{})
      :error

      iex> cast(:string, "beef", %{})
      {:ok, "beef"}
      iex> cast(:binary, "beef", %{})
      {:ok, "beef"}

      iex> cast(:decimal, Decimal.new(1.0), %{})
      {:ok, Decimal.new(1.0)}
      iex> cast(:decimal, Decimal.new("1.0"), %{})
      {:ok, Decimal.new(1.0)}

      iex> cast({:array, :integer}, [1, 2, 3], %{})
      {:ok, [1, 2, 3]}
      iex> cast({:array, :integer}, ["1", "2", "3"], %{})
      {:ok, [1, 2, 3]}
      iex> cast({:array, :string}, [1, 2, 3], %{})
      :error
      iex> cast(:string, [1, 2, 3], %{})
      :error

      iex> cast(:binary_id, "7d5bed50-e8ec-4a74-b863-eb977f3db92e", %{binary_id: Ecto.UUID})
      {:ok, "7d5bed50-e8ec-4a74-b863-eb977f3db92e"}

  """
  @spec cast(t, term, map) :: {:ok, term} | :error
  def cast({:embed, embed}, value, id_types) do
    cast_embed(embed, value, id_types)
  end

  def cast(type, value, id_types) do
    cast(normalize(type, id_types), value)
  end

  defp cast({:array, type}, term) do
    if is_list(term) do
      array(term, &cast(type, &1), [])
    else
      :error
    end
  end

  defp cast(:float, term) when is_binary(term) do
    case Float.parse(term) do
      {float, ""} -> {:ok, float}
      _           -> :error
    end
  end

  defp cast(_type, nil), do: {:ok, nil}

  defp cast(:float, term) when is_integer(term), do: {:ok, term + 0.0}

  defp cast(:boolean, term) when term in ~w(true 1),  do: {:ok, true}
  defp cast(:boolean, term) when term in ~w(false 0), do: {:ok, false}

  defp cast(:decimal, term) when is_binary(term) or is_number(term) do
    {:ok, Decimal.new(term)} # TODO: Add Decimal.parse/1
  rescue
    Decimal.Error -> :error
  end

  defp cast(type, term) when type in [:id, :integer] and is_binary(term) do
    case Integer.parse(term) do
      {int, ""} -> {:ok, int}
      _         -> :error
    end
  end

  defp cast(type, value) do
    cond do
      not primitive?(type) ->
        type.cast(value)
      of_base_type?(type, value) ->
        {:ok, value}
      true ->
        :error
    end
  end

  defp cast_embed(embed, value, _id_types) do
    case Ecto.Embedded.cast(embed, value, nil) do
      {:ok, changesets, true} when is_list(changesets) ->
        Enum.map(changesets, &Ecto.Changeset.apply_changes/1)
      {:ok, changeset, true} ->
        Ecto.Changeset.apply_changes(changeset)
      _ ->
        :error
    end
  end

  @doc """
  Same as `cast/2` but raises if value can't be cast.
  """
  @spec cast!(t, term, map) :: term | no_return
  def cast!(type, term, id_types) do
    case cast(type, term, id_types) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "cannot cast `#{inspect term}` to type #{inspect type}"
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
    raise "cannot dump/cast/load :binary_id type, attempted value: #{inspect value}"
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
end
