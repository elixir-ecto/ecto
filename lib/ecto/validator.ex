defmodule Ecto.Validator do
  @moduledoc """
  Validates a given record or dict given a set of predicates.

      Ecto.Validator.record(user,
        name: present() when on_create?(user),
        age: present(message: "must be present"),
        also: validate_other
      )

  Validations are passed as the second argument in the attribute-predicate
  format. Each predicate can be filtered via the `when` operator. Note `when`
  here is not limited only to guard expressions.

  The predicates above are going to receive the attribute being validated
  and its current value as argument. For example, the `present` predicate
  above is going to be called as:

      present(:name, user.name)
      present(:age, user.age, message: "must be present")

  The validator also handles a special key `:also`, which is used to pipe
  to predicates without a particular attribute. Instead, such predicates
  receive the record as argument. In this example, `validate_other` will
  be invoked as:

      validate_other(user)

  Note all predicates must return a keyword list, with the attribute error
  as key and the validation message as value.

  A handful of predicates can be found at `Ecto.Validator.Predicates`.
  """

  @doc """
  Validates a given record given a set of predicates.
  """
  @spec record(Macro.t, Keyword.t) :: Macro.t
  defmacro record(value, opts) when is_list(opts) do
    process opts, value, fn var, attr ->
      quote do: unquote(var).unquote(attr)
    end
  end

  defp process([], _value, _getter), do: []
  defp process(opts, value, getter) do
    var = quote do: var

    validations = Enum.reduce opts, [], fn i, acc ->
      quote do: unquote(acc) ++ unquote(process_each(i, var, getter))
    end

    quote do
      unquote(var) = unquote(value)
      unquote(validations)
    end
  end

  defp process_each({ :also, function }, var, _getter) do
    handle_when function, fn call -> Macro.pipe(var, call) end
  end

  defp process_each({ attr, function }, var, getter) do
    handle_when function, fn call ->
      Macro.pipe(attr, Macro.pipe(getter.(var, attr), call))
    end
  end

  defp handle_when({ :when, _, [left, right] }, callback) do
    quote do
      if unquote(right), do: unquote(callback.(left)), else: []
    end
  end

  defp handle_when(other, callback) do
    callback.(other)
  end
end
