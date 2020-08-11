defmodule Ecto.ParameterizedTypeTest do
  use ExUnit.Case, async: true

  defmodule MyParameterizedType do
    use Ecto.ParameterizedType

    @params %{some_param: :some_param_value}

    def params, do: @params

    def init([some_opt: :some_opt_value, field: :my_type, schema: _]), do: @params
    def type(@params), do: :custom
    def load(_, _, @params), do: {:ok, :load}
    def dump( _, _, @params),  do: {:ok, :dump}
    def cast( _, @params),  do: {:ok, :cast}
    def equal?(true, _, @params), do: true
    def equal?(_, _, @params), do: false
    def embed_as(_, @params), do: :dump
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
      {:parameterized, Ecto.ParameterizedTypeTest.MyParameterizedType, %{some_param: :some_param_value}}
  end

  @p_type {:parameterized, MyParameterizedType, MyParameterizedType.params()}
  @p_error_type {:parameterized, MyErrorParameterizedType, %{}}

  test "parameterized type" do
    assert Ecto.Type.type(@p_type) == :custom

    assert Ecto.Type.embed_as(@p_type, :foo) == :dump

    assert Ecto.Type.embedded_load(@p_type, :foo, :json) == {:ok, :load}
    assert Ecto.Type.embedded_load(@p_type, nil,  :json) == {:ok, :load}

    assert Ecto.Type.embedded_dump(@p_type, :foo,  :json) == {:ok, :dump}
    assert Ecto.Type.embedded_dump(@p_type, nil, :json) == {:ok, :dump}

    assert Ecto.Type.load(@p_type, :foo) == {:ok, :load}
    assert Ecto.Type.load(@p_type, nil) == {:ok, :load}

    assert Ecto.Type.dump(@p_type, :foo) == {:ok, :dump}
    assert Ecto.Type.dump(@p_type, nil) == {:ok, :dump}

    assert Ecto.Type.cast(@p_type, :foo) == {:ok, :cast}
    assert Ecto.Type.cast(@p_type, nil) == {:ok, :cast}
  end

  test "parameterized type error" do
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

  # TODO: Resolve issue with arrays of parameterized types or delete tests
  @tag :skip
  test "parameterized type with array" do
    assert Ecto.Type.embed_as({:array, @p_type}, :foo) == :self

    assert Ecto.Type.embedded_load({:array, @p_type}, [:foo], :json) == {:ok, [:load]}
    assert Ecto.Type.embedded_load({:array, @p_type}, [nil], :json) == {:ok, [:load]}
    assert Ecto.Type.embedded_load({:array, @p_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.embedded_dump({:array, @p_type}, [:foo], :json) == {:ok, [:dump]}
    assert Ecto.Type.embedded_dump({:array, @p_type}, [nil], :json) == {:ok, [:dump]}
    assert Ecto.Type.embedded_dump({:array, @p_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.load({:array, @p_type}, [:foo]) == {:ok, [:load]}
    assert Ecto.Type.load({:array, @p_type}, [nil]) == {:ok, [:load]}
    assert Ecto.Type.load({:array, @p_type}, nil) == {:ok, nil}

    assert Ecto.Type.dump({:array, @p_type}, [:foo]) == {:ok, [:dump]}
    assert Ecto.Type.dump({:array, @p_type}, [nil]) == {:ok, [:dump]}
    assert Ecto.Type.dump({:array, @p_type}, nil) == {:ok, nil}

    assert Ecto.Type.cast({:array, @p_type}, [:foo]) == {:ok, [:cast]}
    assert Ecto.Type.cast({:array, @p_type}, [nil]) == {:ok, [:cast]}
    assert Ecto.Type.cast({:array, @p_type}, nil) == {:ok, nil}
  end

  # TODO: Resolve issue with map of parameterized types or delete tests
  @tag :skip
  test "parameterized type with map" do
    assert Ecto.Type.embed_as({:map, @p_type}, :foo) == :self

    assert Ecto.Type.embedded_load({:map, @p_type}, %{"x" => "foo"}, :json) == {:ok, %{"x" => :load}}
    assert Ecto.Type.embedded_load({:map, @p_type}, %{"x" => nil}, :json) == {:ok, %{"x" => :load}}
    assert Ecto.Type.embedded_load({:map, @p_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.embedded_dump({:map, @p_type}, %{"x" => "foo"}, :json) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.embedded_dump({:map, @p_type}, %{"x" => nil}, :json) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.embedded_dump({:map, @p_type}, nil, :json) == {:ok, nil}

    assert Ecto.Type.load({:map, @p_type}, %{"x" => "foo"}) == {:ok, %{"x" => :load}}
    assert Ecto.Type.load({:map, @p_type}, %{"x" => nil}) == {:ok, %{"x" => :load}}
    assert Ecto.Type.load({:map, @p_type}, nil) == {:ok, nil}

    assert Ecto.Type.dump({:map, @p_type}, %{"x" => "foo"}) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.dump({:map, @p_type}, %{"x" => nil}) == {:ok, %{"x" => :dump}}
    assert Ecto.Type.dump({:map, @p_type}, nil) == {:ok, %{"x" => :dump}}

    assert Ecto.Type.cast({:map, @p_type}, %{"x" => "foo"}) == {:ok, %{"x" => :cast}}
    assert Ecto.Type.cast({:map, @p_type}, %{"x" => nil}) == {:ok, %{"x" => :cast}}
    assert Ecto.Type.cast({:map, @p_type}, nil) == {:ok, %{"x" => :cast}}
  end

  # TODO: Resolve issue with maybe of parameterized type or delete tests
  @tag :skip
  test "parameterized type with maybe" do
    assert Ecto.Type.embedded_load({:maybe, @p_type}, :foo, :json) == {:ok, :load}
    assert Ecto.Type.embedded_load({:maybe, @p_error_type}, :foo,  :json) == {:ok, :foo}

    assert Ecto.Type.embedded_dump({:maybe, @p_type}, :foo,  :json) == {:ok, :dump}
    assert Ecto.Type.embedded_dump({:maybe, @p_error_type}, :foo, :json) == {:ok, :foo}

    assert Ecto.Type.load({:maybe, @p_type}, :foo) == {:ok, :load}
    assert Ecto.Type.load({:maybe, @p_error_type}, :foo) == {:ok, :foo}

    assert Ecto.Type.dump({:maybe, @p_type}, :foo) == {:ok, :dump}
    assert Ecto.Type.dump({:maybe, @p_error_type}, :foo) == {:ok, :foo}

    assert Ecto.Type.cast({:maybe, @p_type}, :foo) == {:ok, :cast}
    assert Ecto.Type.cast({:maybe, @p_error_type}, :foo) == {:ok, :foo}
  end
end
