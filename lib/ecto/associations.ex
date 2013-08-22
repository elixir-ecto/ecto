defmodule Ecto.Associations do
  @moduledoc """
  Utilities on association.
  """

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.Util

  @doc """
  Returns true if join expression is an assocation join.
  """
  def assoc_join?({ :., _, _ }), do: true
  def assoc_join?(_), do: false

  @doc """
  Returns true if select expression is an assoc selector.
  """
  def assoc_select?({ :assoc, _, [_, _] }), do: true
  def assoc_select?(_), do: false

  @doc """
  Transforms a result set based on the assoc selector, combining the entities
  specified in the assoc selector.
  """
  def transform_result(_expr, [], _query), do: true

  def transform_result({ :assoc, _, [parent, child] }, results, Query[] = query) do
    QueryExpr[expr: join_expr] = Util.find_expr(query, child)
    { :., _, [^parent, field] } = join_expr
    refl = query.from.__ecto__(:association, field)
    field = refl.field

    [{ parent, child }|results] = results
    combine(results, field, parent, [], [child])
  end

  @doc false
  def create_reflection(:has_many, values) do
    Ecto.Reflections.HasMany.new(values)
  end

  def create_reflection(:has_one, values) do
    Ecto.Reflections.HasOne.new(values)
  end

  defp combine([], field, last_parent, parents, children) do
    children = Enum.reverse(children)
    last_parent = set_loaded(last_parent, field, children)
    Enum.reverse([last_parent|parents])
  end

  defp combine([{ parent, child }|rows], field, last_parent, parents, children) do
    if parent.primary_key == last_parent.primary_key do
      combine(rows, field, parent, parents, [child|children])
    else
      children = Enum.reverse(children)
      last_parent = set_loaded(last_parent, field, children)
      parents = [last_parent|parents]
      combine([{ parent, child }|rows], field, parent, parents, [])
    end
  end

  defp set_loaded(record, field, loaded) do
    association = apply(record, field, [])
    association = association.__ecto__(:loaded, loaded)
    apply(record, field, [association])
  end
end
