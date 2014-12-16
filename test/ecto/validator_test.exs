defmodule Ecto.ValidatorTest do
  use ExUnit.Case, async: true

  require Ecto.Validator, as: V

  defmodule User do
    defstruct name: "jose", age: 27
  end

  test "struct with no predicate" do
    assert V.struct(%User{}, []) == nil
  end

  test "struct dispatches to a module predicate" do
    assert V.struct(%User{}, name: present()) == nil
    assert V.struct(%User{name: nil}, name: present()) == %{name: ["can't be blank"]}
  end

  test "struct dispatches to a remote predicate" do
    assert V.struct(%User{}, name: __MODULE__.present()) == nil
    assert V.struct(%User{name: nil}, name: __MODULE__.present()) == %{name: ["can't be blank"]}
  end

  test "struct dispatches to a local predicate" do
    present = &present/2
    assert V.struct(%User{}, name: present.()) == nil
    assert V.struct(%User{name: nil}, name: present.()) == %{name: ["can't be blank"]}
  end

  test "struct handles conditionals" do
    user = %User{age: nil}
    assert V.struct(user, age: present() when user.name != "jose") == nil

    user = %User{name: "eric", age: nil}
    assert V.struct(user, age: present() when user.name != "jose") == %{age: ["can't be blank"]}
  end

  test "struct handles and" do
    user = %User{age: nil}
    assert V.struct(user, age: present() and greater_than(18)) == %{age: ["can't be blank"]}

    user = %User{age: 10}
    assert V.struct(user, age: present() and greater_than(18)) == %{age: ["too big"]}

    user = %User{age: 20}
    assert V.struct(user, age: present() and greater_than(18) and less_than(30)) == nil
  end

  test "struct handles and with conditionals" do
    user = %User{name: "eric", age: nil}
    assert V.struct(user, age: present() and greater_than(18) when user.name != "jose") == %{age: ["can't be blank"]}
  end

  test "struct passes predicate arguments" do
    assert V.struct(%User{name: nil},
                   name: present(message: "must be present")) == %{name: ["must be present"]}
  end

  test "struct is evaluated just once" do
    Process.put(:count, 0)
    assert V.struct((Process.put(:count, Process.get(:count) + 1); %User{}),
             name: present()) == nil
    assert Process.get(:count) == 1
  end

  test "struct dispatches to also" do
    assert V.struct(%User{name: nil, age: nil},
             name: present(),
             also: validate_other) == %{name: ["can't be blank"], age: ["can't be blank"]}

    assert V.struct(%User{name: nil, age: nil},
              also: validate_other and validate_other) == %{age: ["can't be blank", "can't be blank"]}

    assert V.struct(%User{name: "name", age: 6},
              also: validate_other) == nil
  end

  test "validates dicts" do
    assert V.dict([name: nil, age: 27],
                name: present(),
                 age: present()) == %{name: ["can't be blank"]}
  end

  test "validates binary dicts" do
    assert V.bin_dict(%{"name" => nil, "age" => 27},
                    name: present(),
                     age: present()) == %{name: ["can't be blank"]}
  end

  def present(_field, value, opts \\ [])
  def present(_field, nil, opts), do: opts[:message] || "can't be blank"
  def present(_field, _value, _opts), do: nil

  def greater_than(_field, value, min, opts \\ [])
  def greater_than(_field, value, min, _opts) when value > min, do: nil
  def greater_than(_field, _value, _min, opts), do: opts[:message] || "too big"

  def less_than(_field, value, max, opts \\ [])
  def less_than(_field, value, max, _opts) when value < max, do: nil
  def less_than(_field, _value, _max, opts), do: opts[:message] || "too low"

  defp validate_other(struct) do
    V.struct(struct, age: present())
  end
end
