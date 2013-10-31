defmodule Ecto.Query.JoinBuilder do
  @moduledoc false

  alias Ecto.Query.BuilderUtil

  # Escapes a join expression (not including the on expression) returning a pair
  # of `{ binds, expr }`. `binds` is either an empty list or a list of single
  # atom binding. `expr` is either an alias or an association join of format
  # `entity.field`.

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

  def escape(string, _vars) when is_binary(string) do
    { [], string }
  end

  def escape({ { :., _, _ } = assoc, _, [] }, vars) do
    escape(assoc, vars)
  end

  def escape({ :., _, [{ var, _, context }, field] }, vars)
      when is_atom(var) and is_atom(context) and is_atom(field) do
    left_escaped = Ecto.Query.BuilderUtil.escape_var(var, vars)
    assoc = { :{}, [], [:., [], [left_escaped, field]] }
    { [], assoc }
  end

  def escape({ :field, _, [{ var, _, context }, field] }, vars)
      when is_atom(var) and is_atom(context) do
    { [], BuilderUtil.escape_field(var, field, vars) }
  end

  def escape(_other, _vars) do
    raise Ecto.InvalidQuery, reason: "invalid `join` query expression"
  end

  @qualifiers [ :inner, :left, :right, :full ]

  def validate_qual(qual) when qual in @qualifiers, do: :ok
  def validate_qual(_qual) do
    raise Ecto.InvalidQuery, reason: "invalid join qualifier, accepted qualifiers are: " <>
      Enum.map_join(@qualifiers, ", ", &"`#{inspect &1}`")
  end
end
