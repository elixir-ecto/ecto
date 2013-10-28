defmodule Ecto.Validator.Predicates do
  @moduledoc """
  A handful of predicates to be used in validations.

  The examples in this module use the syntax made
  available via `Ecto.Model.Validations` in your
  model.
  """

  @type maybe_error :: [] | Keyword.t
  @blank [nil, "", []]

  @doc """
  Validates the attribute is present (i.e. not nil,
  nor an empty list nor an empty string).

  ## Options

  * `:message` - defaults to "can't be blank"

  ## Examples

      validate user,
        name: present()

  """
  @spec present(atom, term, Keyword.t) :: maybe_error
  def present(attr, value, opts // [])

  def present(attr, value, opts) when value in @blank and is_list(opts) do
    [{ attr, opts[:message] || "can't be blank" }]
  end

  def present(_attr, _value, opts) when is_list(opts) do
    []
  end

  @doc """
  Validates the attribute is absent (i.e. nil,
  an empty list or an empty string).

  ## Options

  * `:message` - defaults to "must be blanke"

  ## Examples

      validate user,
        honeypot: absent()

  """
  @spec absent(atom, term, Keyword.t) :: maybe_error
  def absent(attr, value, opts // [])

  def absent(_attr, value, opts) when value in @blank and is_list(opts) do
    []
  end

  def absent(attr, _value, opts) when is_list(opts) do
    [{ attr, opts[:message] || "must be blank" }]
  end

  @doc """
  Validates the attribute matches a given regular expression.
  Nil values are not matched against (skipped).

  ## Options

  * `:message` - defaults to "is invalid"

  ## Examples

      validate user,
        email: matches(%r/@/)

  """
  @spec matches(atom, term, Regex.t | binary, Keyword.t) :: maybe_error
  def matches(attr, value, match_on, opts // []) when is_regex(match_on) and is_list(opts) do
    if value == nil or Regex.match?(match_on, value) do
      []
    else
      [{ attr, opts[:message] || "is invalid" }]
    end
  end

  @doc """
  Validates the attribute is member of the given enumerable.

  This validator has the same semantics as calling `Enum.member?/2`
  with the given enumerable and value.

  Nil values are not matched against (skipped).

  ## Options

  * `:message` - defaults to "is not included in the list"

  ## Examples

      validate user,
        gender: member_of(%w(male female other))

      validate user,
        age: member_of(0..99)

  """
  @spec member_of(atom, term, Enumerable.t, Keyword.t) :: maybe_error
  def member_of(attr, value, enum, opts // []) when is_list(opts) do
    if value == nil or value in enum do
      []
    else
      [{ attr, opts[:message] || "is not included in the list" }]
    end
  end

  @doc """
  Validates the attribute is not a member of the given enumerable.

  This validator has the same semantics as calling
  `not Enum.member?/2` with the given enumerable and value.

  Nil values are not matched against (skipped).

  ## Options

  * `:message` - defaults to "is reserved"

  ## Examples

      validate user,
        username: not_member_of(%w(admin superuser))

      validate user,
        password: not_member_of([user.username, user.name],
                                message: "cannot be the same as username or first name")

  """
  @spec not_member_of(atom, term, Enumerable.t, Keyword.t) :: maybe_error
  def not_member_of(attr, value, enum, opts // []) when is_list(opts) do
    if value == nil or not(value in enum) do
      []
    else
      [{ attr, opts[:message] || "is reserved" }]
    end
  end
end
