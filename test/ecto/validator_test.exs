defmodule Ecto.ValidatorTest do
  use ExUnit.Case, async: true

  import Ecto.Validator
  defrecord User, name: "jose", age: 27

  test "record with no predicate" do
    assert record(User.new, []) == []
  end

  test "record dispatches to a module predicate" do
    assert record(User.new, name: present()) == []
    assert record(User.new(name: nil), name: present()) == [name: "can't be blank"]
  end

  test "record dispatches to a remote predicate" do
    assert record(User.new, name: __MODULE__.present()) == []
    assert record(User.new(name: nil), name: __MODULE__.present()) == [name: "can't be blank"]
  end

  test "record dispatches to a local predicate" do
    present = &present/2
    assert record(User.new, name: present.()) == []
    assert record(User.new(name: nil), name: present.()) == [name: "can't be blank"]
  end

  test "record handles conditionals" do
    user = User.new(age: nil)
    assert record(user, age: present() when user.name != "jose") == []

    user = User.new(name: "eric", age: nil)
    assert record(user, age: present() when user.name != "jose") == [age: "can't be blank"]
  end

  test "record handles and" do
    user = User.new(age: nil)
    assert record(user, age: present() and greater_than(18)) == [age: "can't be blank"]

    user = User.new(age: 10)
    assert record(user, age: present() and greater_than(18)) == [age: "too big"]

    user = User.new(age: 20)
    assert record(user, age: present() and greater_than(18) and less_than(30)) == []
  end

  test "record passes predicate arguments" do
    assert record(User.new(name: nil),
                   name: present(message: "must be present")) == [name: "must be present"]
  end

  test "record is evaluated just once" do
    Process.put(:count, 0)
    assert record((Process.put(:count, Process.get(:count) + 1); User[]),
             name: present()) == []
    assert Process.get(:count) == 1
  end

  test "record dispatches to also" do
    assert record(User.new(name: nil, age: nil),
             name: present(),
             also: validate_other) == [name: "can't be blank", age: "can't be blank"]

    assert record(User.new(name: nil, age: nil),
              also: validate_other and validate_other) == [age: "can't be blank", age: "can't be blank"]
  end

  test "validates dicts" do
    assert dict([name: nil, age: 27],
                name: present(),
                 age: present()) == [name: "can't be blank"]
  end

  test "validates binary dicts" do
    assert bin_dict([{ "name", nil }, { "age", 27 }],
                    name: present(),
                     age: present()) == [name: "can't be blank"]
  end

  def present(attr, value, opts // [])
  def present(attr, nil, opts), do: [{ attr, opts[:message] || "can't be blank" }]
  def present(_attr, _value, _opts), do: []

  def greater_than(attr, value, min, opts // [])
  def greater_than(_attr, value, min, _opts) when value > min, do: []
  def greater_than(attr, _value, _min, opts), do: [{ attr, opts[:message] || "too big" }]

  def less_than(attr, value, max, opts // [])
  def less_than(_attr, value, max, _opts) when value < max, do: []
  def less_than(attr, _value, _max, opts), do: [{ attr, opts[:message] || "too low" }]

  defp validate_other(record) do
    Ecto.Validator.record(record, age: present())
  end
end
