defmodule Ecto.Validator.PredicatesTest do
  use ExUnit.Case, async: true
  import Ecto.Validator.Predicates

  ## Present

  test "present on invalid" do
    assert present(:name, [])  == [name: "can't be blank"]
    assert present(:name, "")  == [name: "can't be blank"]
    assert present(:name, nil) == [name: "can't be blank"]
  end

  test "present on valid" do
    assert present(:name, "ok") == []
  end

  test "present with custom message" do
    assert present(:name, "", message: "must be present") == [name: "must be present"]
  end

  ## Absent

  test "absent on invalid" do
    assert absent(:name, "ok") == [name: "must be blank"]
  end

  test "absent on valid" do
    assert absent(:name, [])  == []
    assert absent(:name, "")  == []
    assert absent(:name, nil) == []
  end

  test "absent with custom message" do
    assert absent(:name, "ok", message: "are you human?") == [name: "are you human?"]
  end

  ## Matches

  test "matches on invalid" do
    assert matches(:name, "hello world", %r"sample") == [name: "is invalid"]
  end

  test "matches on valid" do
    assert matches(:name, "hello", %r"hello") == []
  end

  test "matches skips on nil" do
    assert matches(:name, nil, %r"hello") == []
  end

  test "matches with custom message with custom message" do
    assert matches(:name, "hello world", %r"sample", message: "no match") == [name: "no match"]
  end

  ## Member of

  test "member_of on invalid" do
    assert member_of(:name, "hello", %w(foo bar baz)) == [name: "is not included in the list"]
    assert member_of(:name, 7, 1..5) == [name: "is not included in the list"]
  end

  test "member_of on valid" do
    assert member_of(:name, "foo", %w(foo bar baz)) == []
    assert member_of(:name, 3, 1..5) == []
  end

  test "member_of skips on nil" do
    assert member_of(:name, nil, %w(foo bar baz)) == []
  end

  test "member_of with custom message with custom message" do
    assert member_of(:name, 7, 1..5, message: "not a member") == [name: "not a member"]
  end

  ## Not member of

  test "not_member_of on invalid" do
    assert not_member_of(:name, "hello", %w(hello world)) == [name: "is reserved"]
    assert not_member_of(:name, 3, 1..5) == [name: "is reserved"]
  end

  test "not_member_of on valid" do
    assert not_member_of(:name, "foo", %w(hello world)) == []
    assert not_member_of(:name, 7, 1..5) == []
  end

  test "not_member_of skips on nil" do
    assert not_member_of(:name, nil, %w(foo bar baz)) == []
  end

  test "not_member_of with custom message with custom message" do
    assert not_member_of(:name, 3, 1..5, message: "is taken") == [name: "is taken"]
  end
end
