defmodule Ecto.ParameterizedTypeTest do
  use ExUnit.Case, async: true

  defmodule MyParameterizedType do
    use Ecto.ParameterizedType

    def params(embed), do: %{embed: embed}
    def init([some_opt: :some_opt_value, field: :my_type, schema: _]), do: :init
    def type(_), do: :custom
    def load(_, _, _), do: {:ok, :load}
    def dump( _, _, _),  do: {:ok, :dump}
    def cast( _, _),  do: {:ok, :cast}
    def equal?(true, _, _), do: true
    def equal?(_, _, _), do: false
    def embed_as(_, %{embed: embed}), do: embed
  end

  defmodule Schema do
    use Ecto.Schema

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "" do
      field :my_type, MyParameterizedType, some_opt: :some_opt_value
    end
  end

  defmodule MyErrorParameterizedType do
    use Ecto.ParameterizedType

    def init(_), do: %{}
    def type(_), do: :custom
    def load(_, _, _), do: :error
    def dump( _, _, _),  do: :error
    def cast( _, _),  do: :error
    def equal?(true, _, _), do: true
    def equal?(_, _, _), do: false
    def embed_as(_, _), do: :self
  end

  test "init" do
    assert Schema.__schema__(:type, :my_type) ==
      {:parameterized, Ecto.ParameterizedTypeTest.MyParameterizedType, :init}
  end

  @p_dump_type {:parameterized, MyParameterizedType, MyParameterizedType.params(:dump)}
  @p_self_type {:parameterized, MyParameterizedType, MyParameterizedType.params(:self)}
  @p_error_type {:parameterized, MyErrorParameterizedType, %{}}

  test "operations" do
    assert Ecto.Type.type(@p_self_type) == :custom
    assert Ecto.Type.type(@p_dump_type) == :custom

    assert Ecto.Type.embed_as(@p_self_type, :foo) == :self
    assert Ecto.Type.embed_as(@p_dump_type, :foo) == :dump

    assert Ecto.Type.embedded_load(@p_self_type, :foo, :json) == {:ok, :cast}
    assert Ecto.Type.embedded_load(@p_self_type, nil,  :json) == {:ok, :cast}
    assert Ecto.Type.embedded_load(@p_dump_type, :foo, :json) == {:ok, :load}
    assert Ecto.Type.embedded_load(@p_dump_type, nil,  :json) == {:ok, :load}

    assert Ecto.Type.embedded_dump(@p_self_type, :foo,  :json) == {:ok, :foo}
    assert Ecto.Type.embedded_dump(@p_self_type, nil, :json) == {:ok, nil}
    assert Ecto.Type.embedded_dump(@p_dump_type, :foo,  :json) == {:ok, :dump}
    assert Ecto.Type.embedded_dump(@p_dump_type, nil, :json) == {:ok, :dump}

    assert Ecto.Type.load(@p_self_type, :foo) == {:ok, :load}
    assert Ecto.Type.load(@p_self_type, nil) == {:ok, :load}

    assert Ecto.Type.dump(@p_self_type, :foo) == {:ok, :dump}
    assert Ecto.Type.dump(@p_self_type, nil) == {:ok, :dump}

    assert Ecto.Type.cast(@p_self_type, :foo) == {:ok, :cast}
    assert Ecto.Type.cast(@p_self_type, nil) == {:ok, :cast}
  end

  test "on error" do
    assert Ecto.Type.type(@p_error_type) == :custom

    assert Ecto.Type.embed_as(@p_error_type, :foo) == :self

    assert Ecto.Type.embedded_load(@p_error_type, :foo, :json) == :error
    assert Ecto.Type.embedded_load(@p_error_type, nil,  :json) == :error

    assert Ecto.Type.embedded_dump(@p_error_type, :foo,  :json) == {:ok, :foo}
    assert Ecto.Type.embedded_dump(@p_error_type, nil, :json) == {:ok, nil}

    assert Ecto.Type.load(@p_error_type, :foo) == :error
    assert Ecto.Type.load(@p_error_type, nil) == :error

    assert Ecto.Type.dump(@p_error_type, :foo) == :error
    assert Ecto.Type.dump(@p_error_type, nil) == :error

    assert Ecto.Type.cast(@p_error_type, :foo) == :error
    assert Ecto.Type.cast(@p_error_type, nil) == :error
  end

  test "with array" do
    assert Ecto.Type.embed_as({:array, @p_self_type}, :foo) == :self
    assert Ecto.Type.embed_as({:array, @p_dump_type}, :foo) == :dump
    assert Ecto.Type.embed_as({:array, @p_error_type}, :foo) == :self

    assert Ecto.Type.embedded_load({:array, @p_self_type}, [:foo], :json) == {:ok, [:cast]}
    assert Ecto.Type.embedded_load({:array, @p_self_type}, [nil], :json) == {:ok, [:cast]}
    assert Ecto.Type.embedded_load({:array, @p_self_type}, nil, :json) == {:ok, nil}
    assert Ecto.Type.embedded_load({:array, @p_dump_type}, [:foo], :json) == {:ok, [:load]}
    assert Ecto.Type.embedded_load({:array, @p_dump_type}, [nil], :json) == {:ok, [:load]}
    assert Ecto.Type.embedded_load({:array, @p_dump_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.embedded_dump({:array, @p_self_type}, [:foo], :json) == {:ok, [:foo]}
    assert Ecto.Type.embedded_dump({:array, @p_self_type}, [nil], :json) == {:ok, [nil]}
    assert Ecto.Type.embedded_dump({:array, @p_self_type}, nil, :json) == {:ok, nil}
    assert Ecto.Type.embedded_dump({:array, @p_dump_type}, [:foo], :json) == {:ok, [:dump]}
    assert Ecto.Type.embedded_dump({:array, @p_dump_type}, [nil], :json) == {:ok, [:dump]}
    assert Ecto.Type.embedded_dump({:array, @p_dump_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.load({:array, @p_self_type}, [:foo]) == {:ok, [:load]}
    assert Ecto.Type.load({:array, @p_self_type}, [nil]) == {:ok, [:load]}
    assert Ecto.Type.load({:array, @p_self_type}, nil) == {:ok, nil}

    assert Ecto.Type.dump({:array, @p_self_type}, [:foo]) == {:ok, [:dump]}
    assert Ecto.Type.dump({:array, @p_self_type}, [nil]) == {:ok, [:dump]}
    assert Ecto.Type.dump({:array, @p_self_type}, nil) == {:ok, nil}

    assert Ecto.Type.cast({:array, @p_self_type}, [:foo]) == {:ok, [:cast]}
    assert Ecto.Type.cast({:array, @p_self_type}, [nil]) == {:ok, [:cast]}
    assert Ecto.Type.cast({:array, @p_self_type}, nil) == {:ok, nil}
  end

  test "with map" do
    assert Ecto.Type.embed_as({:map, @p_dump_type}, :foo) == :dump
    assert Ecto.Type.embed_as({:map, @p_error_type}, :foo) == :self

    assert Ecto.Type.embedded_load({:map, @p_self_type}, %{"x" => "foo"}, :json) == {:ok, %{"x" => :cast}}
    assert Ecto.Type.embedded_load({:map, @p_self_type}, %{"x" => nil}, :json) == {:ok, %{"x" => :cast}}
    assert Ecto.Type.embedded_load({:map, @p_self_type}, nil, :json) == {:ok, nil}
    assert Ecto.Type.embedded_load({:map, @p_dump_type}, %{"x" => "foo"}, :json) == {:ok, %{"x" => :load}}
    assert Ecto.Type.embedded_load({:map, @p_dump_type}, %{"x" => nil}, :json) == {:ok, %{"x" => :load}}
    assert Ecto.Type.embedded_load({:map, @p_dump_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.embedded_dump({:map, @p_self_type}, %{"x" => "foo"}, :json) == {:ok, %{"x" => "foo"}}
    assert Ecto.Type.embedded_dump({:map, @p_self_type}, %{"x" => nil}, :json) == {:ok, %{"x" => nil}}
    assert Ecto.Type.embedded_dump({:map, @p_self_type}, nil, :json) == {:ok, nil}
    assert Ecto.Type.embedded_dump({:map, @p_dump_type}, %{"x" => "foo"}, :json) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.embedded_dump({:map, @p_dump_type}, %{"x" => nil}, :json) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.embedded_dump({:map, @p_dump_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.load({:map, @p_self_type}, %{"x" => "foo"}) == {:ok, %{"x" => :load}}
    assert Ecto.Type.load({:map, @p_self_type}, %{"x" => nil}) == {:ok, %{"x" => :load}}
    assert Ecto.Type.load({:map, @p_self_type}, nil) == {:ok, nil}

    assert Ecto.Type.dump({:map, @p_self_type}, %{"x" => "foo"}) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.dump({:map, @p_self_type}, %{"x" => nil}) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.dump({:map, @p_self_type}, nil) == {:ok, nil}

    assert Ecto.Type.cast({:map, @p_self_type}, %{"x" => "foo"}) == {:ok, %{"x" => :cast}}
    assert Ecto.Type.cast({:map, @p_self_type}, %{"x" => nil}) == {:ok, %{"x" => :cast}}
    assert Ecto.Type.cast({:map, @p_self_type}, nil) == {:ok, nil}
  end

  test "with maybe" do
    assert Ecto.Type.embedded_load({:maybe, @p_self_type}, :foo, :json) == {:ok, :cast}
    assert Ecto.Type.embedded_load({:maybe, @p_dump_type}, :foo, :json) == {:ok, :load}
    assert Ecto.Type.embedded_load({:maybe, @p_error_type}, :foo,  :json) == {:ok, :foo}

    assert Ecto.Type.embedded_dump({:maybe, @p_self_type}, :foo,  :json) == {:ok, :foo}
    assert Ecto.Type.embedded_dump({:maybe, @p_dump_type}, :foo,  :json) == {:ok, :dump}
    assert Ecto.Type.embedded_dump({:maybe, @p_error_type}, :foo, :json) == {:ok, :foo}

    assert Ecto.Type.load({:maybe, @p_self_type}, :foo) == {:ok, :load}
    assert Ecto.Type.load({:maybe, @p_error_type}, :foo) == {:ok, :foo}

    assert Ecto.Type.dump({:maybe, @p_self_type}, :foo) == {:ok, :dump}
    assert Ecto.Type.dump({:maybe, @p_error_type}, :foo) == {:ok, :foo}

    assert Ecto.Type.cast({:maybe, @p_self_type}, :foo) == {:ok, :cast}
    assert Ecto.Type.cast({:maybe, @p_error_type}, :foo) == {:ok, :foo}
  end

  defmodule MyParameterizedTypeForPrimaryKey do
    use Ecto.ParameterizedType

    def init(
          primary_key: true,
          autogenerate: true,
          some_opt: :some_opt_value,
          field: :id,
          schema: _
        ),
        do: :init

    def type(_), do: :id
    def load(_, _, _), do: {:ok, :load}
    def dump(_, _, _), do: {:ok, :dump}
    def cast(_, _), do: {:ok, :cast}
  end

  defmodule SchemaWithParameterizedTypeAsPrimaryKey do
    use Ecto.Schema

    @primary_key {:id, MyParameterizedTypeForPrimaryKey,
                  autogenerate: true, some_opt: :some_opt_value}
    schema "" do
    end
  end

  test "init primary key field" do
    assert SchemaWithParameterizedTypeAsPrimaryKey.__schema__(:autogenerate_id) ==
             {:id, :id,
              {:parameterized, Ecto.ParameterizedTypeTest.MyParameterizedTypeForPrimaryKey, :init}}
  end
end
