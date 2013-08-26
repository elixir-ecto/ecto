defmodule Ecto.Associations do
  @moduledoc """
  Utilities on association.
  """

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr
  alias Ecto.Query.AssocJoinExpr
  alias Ecto.Query.Util
  alias Ecto.Reflections.HasOne
  alias Ecto.Reflections.HasMany

  @doc """
  Returns true if join expression is an assocation join.
  """
  def assoc_join?({ :., _, _ }), do: true
  def assoc_join?({ :{}, _, [:., _, _] }), do: true
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
    AssocJoinExpr[expr: join_expr] = Util.find_expr(query, child)
    { :., _, [^parent, field] } = join_expr
    refl = query.from.__ecto__(:association, field)

    [{ parent, child }|results] = results
    combine(results, refl, parent, [], [child])
  end

  @doc false
  def create_reflection(type, name, module, pk, assoc, fk)
      when type in [:has_many, :has_one] do
    module_name = module |> Module.split |> List.last |> String.downcase
    values = [
      owner: module,
      associated: assoc,
      foreign_key: fk || :"#{module_name}_#{pk}",
      field: :"__#{name}__" ]

    case type do
      :has_many -> Ecto.Reflections.HasMany.new(values)
      :has_one  -> Ecto.Reflections.HasOne.new(values)
    end
  end

  def create_reflection(:belongs_to, name, module, _pk, assoc, fk) do
    values = [
      owner: module,
      associated: assoc,
      foreign_key: fk,
      field: :"__#{name}__" ]
    Ecto.Reflections.BelongsTo.new(values)
  end

  defp combine([], refl, last_parent, parents, children) do
    children = Enum.reverse(children)
    last_parent = set_loaded(last_parent, refl, children)
    Enum.reverse([last_parent|parents])
  end

  defp combine([{ parent, child }|rows], refl, last_parent, parents, children) do
    if parent.primary_key == last_parent.primary_key do
      combine(rows, refl, parent, parents, [child|children])
    else
      children = Enum.reverse(children)
      last_parent = set_loaded(last_parent, refl, children)
      parents = [last_parent|parents]
      combine([{ parent, child }|rows], refl, parent, parents, [])
    end
  end

  defp set_loaded(record, HasOne[field: field], loaded) do
    loaded = case loaded do
      [] -> nil
      [elem] -> elem
    end
    set_loaded(record, field, loaded)
  end

  defp set_loaded(record, HasMany[field: field], loaded) do
    set_loaded(record, field, loaded)
  end

  defp set_loaded(record, field, loaded) do
    association = apply(record, field, [])
    association = association.__ecto__(:loaded, loaded)
    apply(record, field, [association])
  end
end
