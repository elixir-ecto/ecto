defmodule Ecto.Validator.PredicatesTest do
  use ExUnit.Case, async: true
  import Ecto.Validator.Predicates

  ## Present

  test "present on invalid" do
    assert present([])  == "can't be blank"
    assert present("")  == "can't be blank"
    assert present(nil) == "can't be blank"
  end

  test "present on valid" do
    assert present("ok") == nil
  end

  test "present with custom message" do
    assert present("", message: "must be present") == "must be present"
  end

  ## Absent

  test "absent on invalid" do
    assert absent("ok") == "must be blank"
  end

  test "absent on valid" do
    assert absent([])  == nil
    assert absent("")  == nil
    assert absent(nil) == nil
  end

  test "absent with custom message" do
    assert absent("ok", message: "are you human?") == "are you human?"
  end

  ## Has format

  test "has_format on invalid" do
    assert has_format("hello world", ~r"sample") == "is invalid"
  end

  test "has_format on valid" do
    assert has_format("hello", ~r"hello") == nil
  end

  test "has_format skips on nil" do
    assert has_format(nil, ~r"hello") == nil
  end

  test "has_format with custom message" do
    assert has_format("hello world", ~r"sample", message: "no match") == "no match"
  end

  ## Has length

  test "has_length with range on invalid" do
    assert has_length("hello", 1..3) == "is too long (maximum is 3 characters)"
    assert has_length("hello", 7..9) == "is too short (minimum is 7 characters)"
  end

  test "has_length with range on valid" do
    assert has_length("hello", 3..7) == nil
  end

  test "has_length with range with custom message" do
    assert has_length("hello", 1..3, too_long: "is too long") == "is too long"
    assert has_length("hello", 7..9, too_short: "is too short") == "is too short"
  end

  test "has_length with opts on invalid" do
    assert has_length("hello", min: 1, max: 3) == "is too long (maximum is 3 characters)"
    assert has_length("hello", min: 7, max: 9) == "is too short (minimum is 7 characters)"
  end

  test "has_length with opts on valid" do
    assert has_length("hello", min: 3, max: 7) == nil
  end

  test "has_length with opts with custom message" do
    assert has_length("hello", [min: 1, max: 3], too_long: "is too long") == "is too long"
    assert has_length("hello", min: 7, max: 9, too_short: "is too short") == "is too short"
  end

  test "has_length with integer on invalid" do
    assert has_length("hello", 3) == "must be 3 characters"
  end

  test "has_length with integer on valid" do
    assert has_length("hello", 5) == nil
  end

  test "has_length with integer with custom message" do
    assert has_length("hello", 3, no_match: "is wrong") == "is wrong"
  end

  test "has_length handles pluralization" do
    assert has_length("hello", 1) == "must be 1 character"
  end

  test "has_length skips on nil" do
    assert has_length(nil, 3..5) == nil
  end

  ## Member of

  test "member_of on invalid" do
    assert member_of("hello", ~w(foo bar baz)) == "is not included in the list"
    assert member_of(7, 1..5) == "is not included in the list"
  end

  test "member_of on valid" do
    assert member_of("foo", ~w(foo bar baz)) == nil
    assert member_of(3, 1..5) == nil
  end

  test "member_of skips on nil" do
    assert member_of(nil, ~w(foo bar baz)) == nil
  end

  test "member_of with custom message" do
    assert member_of(7, 1..5, message: "not a member") == "not a member"
  end

  ## Greater than

  test "greater_than on invalid" do
    assert greater_than(5, 10)  == "must be greater than 10"
    assert greater_than(10, 10) == "must be greater than 10"
    assert greater_than(89.98, 99.98) == "must be greater than 99.98"
    assert greater_than(89.98, 89.98) == "must be greater than 89.98"
  end

  test "greater_than on valid" do
    assert greater_than(5, 0) == nil
    assert greater_than(89.98, 79.98) == nil
  end

  test "greater_than skips on nil" do
    assert greater_than(nil, 10) == nil
  end

  test "greater_than with custom message" do
    assert greater_than(5, 10, message: "bad number") == "bad number"
  end

  ## Greater than or equal to

  test "greater_than_or_equal_to on invalid" do
    assert greater_than_or_equal_to(5, 10) == "must be greater than or equal to 10"
    assert greater_than_or_equal_to(89.98, 99.98) == "must be greater than or equal to 99.98"
  end

  test "greater_than_or_equal_to on valid" do
    assert greater_than_or_equal_to(5, 0) == nil
    assert greater_than_or_equal_to(5, 5) == nil
    assert greater_than_or_equal_to(89.98, 79.98) == nil
    assert greater_than_or_equal_to(89.98, 89.98) == nil
  end

  test "greater_than_or_equal_to skips on nil" do
    assert greater_than_or_equal_to(nil, 10) == nil
  end

  test "greater_than_or_equal_to with custom message" do
    assert greater_than_or_equal_to(5, 10, message: "bad number") == "bad number"
  end

  ## Less than

  test "less_than on invalid" do
    assert less_than(10, 5)  == "must be less than 5"
    assert less_than(10, 10) == "must be less than 10"
    assert less_than(89.98, 79.98) == "must be less than 79.98"
    assert less_than(89.98, 89.98) == "must be less than 89.98"
  end

  test "less_than on valid" do
    assert less_than(0, 5) == nil
    assert less_than(89.98, 99.98) == nil
  end

  test "less_than skips on nil" do
    assert less_than(nil, 10) == nil
  end

  test "less_than with custom message" do
    assert less_than(10, 5, message: "bad number") == "bad number"
  end

  ## Less than or equal to

  test "less_than_or_equal_to on invalid" do
    assert less_than_or_equal_to(10, 5) == "must be less than or equal to 5"
    assert less_than_or_equal_to(89.98, 79.98) == "must be less than or equal to 79.98"
  end

  test "less_than_or_equal_to on valid" do
    assert less_than_or_equal_to(0, 5) == nil
    assert less_than_or_equal_to(5, 5) == nil
    assert less_than_or_equal_to(89.98, 99.98) == nil
    assert less_than_or_equal_to(89.98, 89.98) == nil
  end

  test "less_than_or_equal_to skips on nil" do
    assert less_than_or_equal_to(nil, 10) == nil
  end

  test "less_than_or_equal_to with custom message" do
    assert less_than_or_equal_to(10, 5, message: "bad number") == "bad number"
  end

  ## Between

  test "between on invalid" do
    assert between(25, 18..21) == "must be between 18 and 21"
    assert between(99.98, 79.98..89.98) == "must be between 79.98 and 89.98"
  end

  test "between on valid" do
    assert between(19, 18..21) == nil
    assert between(80.00, 79.98..89.98) == nil
  end

  test "between skips on nil" do
    assert between(nil, 18..21) == nil
  end

  test "between with custom message" do
    assert between(24, 18..21, message: "bad number") == "bad number"
  end

  ## Not member of

  test "not_member_of on invalid" do
    assert not_member_of("hello", ~w(hello world)) == "is reserved"
    assert not_member_of(3, 1..5) == "is reserved"
  end

  test "not_member_of on valid" do
    assert not_member_of("foo", ~w(hello world)) == nil
    assert not_member_of(7, 1..5) == nil
  end

  test "not_member_of skips on nil" do
    assert not_member_of(nil, ~w(foo bar baz)) == nil
  end

  test "not_member_of with custom message" do
    assert not_member_of(3, 1..5, message: "is taken") == "is taken"
  end
end
