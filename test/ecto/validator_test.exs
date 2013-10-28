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
  end

  test "validates dicts" do
    assert dict([name: nil, age: 27],
                name: present(),
                 age: present()) == [name: "can't be blank"]
  end

  def present(attr, value, opts // [])
  def present(attr, nil, opts), do: [{ attr, opts[:message] || "can't be blank" }]
  def present(_attr, _value, _opts), do: []

  defp validate_other(record) do
    Ecto.Validator.record(record, age: present())
  end
end