defmodule Ecto.Validator.Predicates do
  require Ecto.Query

  @moduledoc """
  A handful of predicates to be used in validations.

  The examples in this module use the syntax made
  available via `Ecto.Model.Validations` in your
  model.
  """

  @type field :: atom
  @type maybe_error :: nil | binary
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
  @spec present(field, term, Keyword.t) :: maybe_error
  def present(field, value, opts \\ [])

  def present(_field, value, opts) when value in @blank and is_list(opts) do
    opts[:message] || "can't be blank"
  end

  def present(_field, _value, opts) when is_list(opts) do
    nil
  end

  @doc """
  Validates the attribute is absent (i.e. nil,
  an empty list or an empty string).

  ## Options

  * `:message` - defaults to "must be blank"

  ## Examples

      validate user,
        honeypot: absent()

  """
  @spec absent(field, term, Keyword.t) :: maybe_error
  def absent(field, value, opts \\ [])

  def absent(_field, value, opts) when value in @blank and is_list(opts) do
    nil
  end

  def absent(_field, _value, opts) when is_list(opts) do
    opts[:message] || "must be blank"
  end

  @doc """
  Validates the attribute has a given format.
  Nil values are not matched against (skipped).

  ## Options

  * `:message` - defaults to "is invalid"

  ## Examples

      validate user,
        email: has_format(~r/@/)

  """
  @spec has_format(field, term, Regex.t | binary, Keyword.t) :: maybe_error
  def has_format(_field, value, match_on, opts \\ []) when is_list(opts) do
    unless value == nil or value =~ match_on do
      opts[:message] || "is invalid"
    end
  end

  @doc """
  Validates the attribute has a given length according to Unicode
  (i.e. it uses `String.length` under the scenes). That said, this
  function should not be used to validate binary fields.

  The length can be given as a range (indicating min and max),
  as an integer (indicating exact match) or as keyword options,
  indicating, min and max values.

  Raises if the given argument is not a binary.

  ## Options

  * `:too_long`  - message when the length is too long
                   (defaults to "is too long (maximum is X characters)")
  * `:too_short` - message when the length is too short
                   (defaults to "is too short (minimum is X characters)")
  * `:no_match` - message when the length does not match
                  (defaults to "must be X characters")

  ## Examples

      validate user,
        password: has_length(6..100)

      validate user,
        password: has_length(min: 6, too_short: "requires a minimum length")

      validate user,
        code: has_length(3, no_match: "needs to be 3 characters")

  """
  @spec has_length(field, term, Range.t | number, Keyword.t) :: maybe_error
  def has_length(_field, value, match_on, opts \\ [])

  def has_length(_field, nil, _match_on, opts) when is_list(opts) do
    nil
  end

  def has_length(_field, value, min..max, opts) when is_binary(value) when is_list(opts) do
    length = String.length(value)
    too_short(length, min, opts) || too_long(length, max, opts)
  end

  def has_length(_field, value, exact, opts) when is_integer(exact) do
    if String.length(value) != exact do
      opts[:no_match] || "must be #{characters(exact)}"
    end
  end

  def has_length(_field, value, opts, other) when is_list(opts) and is_list(other) do
    opts   = Keyword.merge(opts, other)
    length = String.length(value)
    ((min = opts[:min]) && too_short(length, min, opts)) ||
    ((max = opts[:max]) && too_long(length, max, opts))
  end

  defp too_short(length, min, opts) when is_integer(min) do
    if length < min do
      opts[:too_short] || "is too short (minimum is #{characters(min)})"
    end
  end

  defp too_long(length, max, opts) when is_integer(max) do
    if length > max do
      opts[:too_long] || "is too long (maximum is #{characters(max)})"
    end
  end

  defp characters(1), do: "1 character"
  defp characters(x), do: "#{x} characters"

  @doc """
  Validates the given number is greater than the given value.
  Expects numbers as value, raises otherwise.

  ## Options

  * `:message` - defaults to "must be greater than X"

  ## Examples

      validates user,
          age: greater_than(18)

  """
  @spec greater_than(field, number, Keyword.t) :: maybe_error
  def greater_than(_field, value, check, opts \\ [])
  def greater_than(_field, value, check, _opts) when
        is_number(check) and (is_nil(value) or value > check), do: nil
  def greater_than(_field, _value, check, opts) when is_number(check) do
    opts[:message] || "must be greater than #{check}"
  end

  @doc """
  Validates the given number is greater than or equal to the given value.
  Expects numbers as value, raises otherwise.

  ## Options

  * `:message` - defaults to "must be greater than or equal to X"

  ## Examples

      validates user,
          age: greater_than_or_equal_to(18)

  """
  @spec greater_than_or_equal_to(field, number, Keyword.t) :: maybe_error
  def greater_than_or_equal_to(_field, value, check, opts \\ [])
  def greater_than_or_equal_to(_field, value, check, _opts) when
        is_number(check) and (is_nil(value) or value >= check), do: nil
  def greater_than_or_equal_to(_field, _value, check, opts) when is_number(check) do
    opts[:message] || "must be greater than or equal to #{check}"
  end

  @doc """
  Validates the given number is less than the given value.
  Expects numbers as value, raises otherwise.

  ## Options

  * `:message` - defaults to "must be less than X"

  ## Examples

      validates user,
          age: less_than(18)

  """
  @spec less_than(field, number, Keyword.t) :: maybe_error
  def less_than(_field, value, check, opts \\ [])
  def less_than(_field, value, check, _opts) when
        is_number(check) and (is_nil(value) or value < check), do: nil
  def less_than(_field, _value, check, opts) when is_number(check) do
    opts[:message] || "must be less than #{check}"
  end

  @doc """
  Validates the given number is less than or equal to the given value.
  Expects numbers as value, raises otherwise.

  ## Options

  * `:message` - defaults to "must be less than or equal to X"

  ## Examples

      validates user,
          age: less_than_or_equal_to(18)

  """
  @spec less_than_or_equal_to(field, number, Keyword.t) :: maybe_error
  def less_than_or_equal_to(_field, value, check, opts \\ [])
  def less_than_or_equal_to(_field, value, check, _opts) when
        is_number(check) and (is_nil(value) or value <= check), do: nil
  def less_than_or_equal_to(_field, _value, check, opts) when is_number(check) do
    opts[:message] || "must be less than or equal to #{check}"
  end

  @doc """
  Validates the given number is between the value.
  Expects a range as value, raises otherwise.

  ## Options

  * `:message` - defaults to "must be between X and Y"

  ## Examples

      validates user,
          age: between(18..21)

  """
  @spec between(field, Range.t, Keyword.t) :: maybe_error
  def between(_field, value, range, opts \\ [])
  def between(_field, value, min..max, _opts) when
    is_number(min) and is_number(max) and (is_nil(value) or value in min..max), do: nil
  def between(_field, _value, min..max, opts) when is_number(min) and is_number(max) do
    opts[:message] || "must be between #{min} and #{max}"
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
        gender: member_of(~w(male female other))

      validate user,
        age: member_of(0..99)

  """
  @spec member_of(field, term, Enumerable.t, Keyword.t) :: maybe_error
  def member_of(_field, value, enum, opts \\ []) when is_list(opts) do
    unless value == nil or value in enum do
      opts[:message] || "is not included in the list"
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
        username: not_member_of(~w(admin superuser))

      validate user,
        password: not_member_of([user.username, user.name],
                                message: "cannot be the same as username or first name")

  """
  @spec not_member_of(field, term, Enumerable.t, Keyword.t) :: maybe_error
  def not_member_of(_field, value, enum, opts \\ []) when is_list(opts) do
    unless value == nil or not(value in enum) do
      opts[:message] || "is reserved"
    end
  end

  @doc """
  Validates the attribute given model are unique..

  ## Options

  * `:case_sensitive` - defaults true
  * `:message` - defaults "already taken"
  * `:on` - repo to query against
  * `:scope` - defaults to []


  ## Examples

      validate user,
        also: unique([:email], on: Repo)

      validate user,
        also: unique([:email, :username], on: Repo)

  """
  def unique(model, fields, opts \\ []) when is_list(opts) do
    module         = model.__struct__
    repo           = Keyword.fetch!(opts, :on)
    scope          = opts[:scope] || []
    message        = opts[:message] || "already taken"
    case_sensitive = Keyword.get(opts, :case_sensitive, true)

    where =
      Enum.reduce(fields, false, fn field, acc ->
        value = Map.fetch!(model, field)
        if case_sensitive and is_binary(value) do
          quote(do: unquote(acc) or downcase(&0.unquote(field)) == downcase(unquote(value)))
        else
          quote(do: unquote(acc) or &0.unquote(field) == unquote(value))
        end
      end)

    where =
      Enum.reduce(scope, where, fn field, acc ->
        value = Map.fetch!(model, field)
        quote(do: unquote(acc) and &0.unquote(field) == unquote(value))
      end)

    select = Enum.map(fields, fn field -> quote(do: &0.unquote(field)) end)

    query = %{Ecto.Query.from(module, limit: 1) |
      select: %Ecto.Query.QueryExpr{expr: select},
      wheres: [%Ecto.Query.QueryExpr{expr: where}]}

    case repo.all(query) do
      [values] ->
        zipped = Enum.zip(fields, values)
        Enum.reduce(zipped, Map.new,  fn {field, value}, acc ->
          if Map.fetch!(model, field) == value do 
            Map.put(acc, field, message)
          else
            acc
          end
        end)
      _ ->
        nil
    end
  end
end
