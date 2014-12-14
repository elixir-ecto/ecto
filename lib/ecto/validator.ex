defmodule Ecto.Validator do
  @moduledoc """
  Validates a given struct or dict given a set of predicates.

      Ecto.Validator.struct(user,
        name: present() when on_create?(user),
        age: present(message: "must be present"),
        age: greater_than(18),
        also: validate_other
      )

  Validations are passed as the second argument in the attribute-predicate
  format. Each predicate can be filtered via the `when` operator. Note `when`
  here is not limited to only guard expressions.

  The predicates above are going to receive the attribute being validated
  and its current value as argument. For example, the `present` predicate
  above is going to be called as:

      present(:name, user.name)
      present(:age, user.age, message: "must be present")

  The validator also handles a special key `:also`, which is used to pipe
  to predicates without a particular attribute. Instead, such predicates
  receive the struct as argument. In this example, `validate_other` will
  be invoked as:

      validate_other(user)

  Note all predicates must return a keyword list, with the attribute error
  as key and the validation message as value.

  A handful of predicates can be found at `Ecto.Validator.Predicates`.
  """

  @doc """
  Validates a given dict given a set of predicates.
  """
  @spec dict(Macro.t, Keyword.t) :: Macro.t
  defmacro dict(value, opts) when is_list(opts) do
    process opts, value, fn var, attr ->
      quote do: Dict.get(unquote(var), unquote(attr))
    end
  end

  @doc """
  Validates a given dict, with binary keys, given a set of predicates.
  """
  @spec bin_dict(Macro.t, Keyword.t) :: Macro.t
  defmacro bin_dict(value, opts) when is_list(opts) do
    process opts, value, fn var, attr ->
      quote do: Dict.get(unquote(var), unquote(Atom.to_string(attr)))
    end
  end

  @doc """
  Validates a given struct given a set of predicates.
  """
  @spec struct(Macro.t, Keyword.t) :: Macro.t
  defmacro struct(value, opts) when is_list(opts) do
    process opts, value, fn var, attr ->
      quote do: Map.get(unquote(var), unquote(attr))
    end
  end

  defp process([], _value, _getter), do: nil
  defp process(opts, value, getter) do
    var = quote do: var

    validations =
      Enum.reduce(opts, quote(do: %{}), &process_each(&1, &2, var, getter))

    quote do
      unquote(var) = unquote(value)
      if map_size(errors = unquote(validations)) > 0 do
        errors
      end
    end
  end

  defp process_each({:also, function}, acc, var, _getter) do
    quotation = fn acc, predicate ->
      quote do
        acc = unquote(acc)
        case unquote(predicate) do
          nil -> acc
          err -> Map.merge(acc, err, fn _k, v1, v2 -> v1 ++ v2 end)
        end
      end
    end

    handle_ops function, acc, quotation, fn call ->
      Macro.pipe(var, call, 0)
    end
  end

  defp process_each({attr, function}, acc, var, getter) do
    quotation = fn acc, predicate ->
      quote do
        acc = unquote(acc)
        case unquote(predicate) do
          nil -> acc
          msg -> Map.update(acc, unquote(attr), [msg], &[msg|&1])
        end
      end
    end

    handle_ops function, acc, quotation, fn call ->
      Macro.pipe(getter.(var, attr), call, 0)
    end
  end

  defp handle_ops({:when, _, [left, right]}, acc, quotation, builder) do
    quote do
      if unquote(right) do
        unquote(handle_and(left, acc, quotation, builder))
      else
        unquote(acc)
      end
    end
  end

  defp handle_ops(other, acc, quotation, builder) do
    handle_and(other, acc, quotation, builder)
  end

  defp handle_and({:and, _, [left, right]}, acc, quotation, builder) do
    handle_and(left, quotation.(acc, builder.(right)), quotation, builder)
  end

  defp handle_and(other, acc, quotation, builder) do
    quotation.(acc, builder.(other))
  end
end
