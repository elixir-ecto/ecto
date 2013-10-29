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

  ## Has format

  test "has_format on invalid" do
    assert has_format(:name, "hello world", %r"sample") == [name: "is invalid"]
  end

  test "has_format on valid" do
    assert has_format(:name, "hello", %r"hello") == []
  end

  test "has_format skips on nil" do
    assert has_format(:name, nil, %r"hello") == []
  end

  test "has_format with custom message" do
    assert has_format(:name, "hello world", %r"sample", message: "no match") == [name: "no match"]
  end

  ## Has length

  test "has_length with range on invalid" do
    assert has_length(:name, "hello", 1..3) == [name: "is too long (maximum is 3 characters)"]
    assert has_length(:name, "hello", 7..9) == [name: "is too short (minimum is 7 characters)"]
  end

  test "has_length with range on valid" do
    assert has_length(:name, "hello", 3..7) == []
  end

  test "has_length with range with custom message" do
    assert has_length(:name, "hello", 1..3, too_long: "is too long") == [name: "is too long"]
    assert has_length(:name, "hello", 7..9, too_short: "is too short") == [name: "is too short"]
  end

  test "has_length with opts on invalid" do
    assert has_length(:name, "hello", min: 1, max: 3) == [name: "is too long (maximum is 3 characters)"]
    assert has_length(:name, "hello", min: 7, max: 9) == [name: "is too short (minimum is 7 characters)"]
  end

  test "has_length with opts on valid" do
    assert has_length(:name, "hello", min: 3, max: 7) == []
  end

  test "has_length with opts with custom message" do
    assert has_length(:name, "hello", [min: 1, max: 3], too_long: "is too long") == [name: "is too long"]
    assert has_length(:name, "hello", min: 7, max: 9, too_short: "is too short") == [name: "is too short"]
  end

  test "has_length with integer on invalid" do
    assert has_length(:name, "hello", 3) == [name: "must be 3 characters"]
  end

  test "has_length with integer on valid" do
    assert has_length(:name, "hello", 5) == []
  end

  test "has_length with integer with custom message" do
    assert has_length(:name, "hello", 3, no_match: "is wrong") == [name: "is wrong"]
  end

  test "has_length handles pluralization" do
    assert has_length(:name, "hello", 1) == [name: "must be 1 character"]
  end

  test "has_length skips on nil" do
    assert has_length(:name, nil, 3..5) == []
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

  test "member_of with custom message" do
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

  test "not_member_of with custom message" do
    assert not_member_of(:name, 3, 1..5, message: "is taken") == [name: "is taken"]
  end
end
