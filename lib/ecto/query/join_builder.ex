defmodule Ecto.Query.JoinBuilder do
  @moduledoc false

  def escape({ :in, _, [{ var, _, context }, expr] }, vars)
      when is_atom(var) and is_atom(context) do
    { [var], escape(expr, vars) |> elem(1) }
  end

  def escape({ :in, _, [{ var, _, context }, expr] }, vars)
      when is_atom(var) and is_atom(context) do
    { [var], escape(expr, vars) |> elem(1) }
  end

  def escape({ :__aliases__, _, _ } = module, _vars) do
    { [], module }
  end

  def escape({ { :., _, _ } = assoc, _, [] }, vars) do
    escape(assoc, vars)
  end

  def escape({ :., _, [{ var, _, context }, field] }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    ix = Enum.find_index(vars, &(&1 == var))
    unless ix do
      raise Ecto.InvalidQuery, reason: "variable `#{var}` needs to be bound"
    end

    left_escaped = { :{}, [], [:&, [], [ix]] }
    assoc = { :{}, [], [:., [], [left_escaped, field]] }
    { [], assoc }
  end

  def escape(_other, _vars) do
    raise Ecto.InvalidQuery, reason: "invalid `join` query expression"
  end

  def assoc_join?({ :., _, _ }), do: true
  def assoc_join?(_), do: false
end
