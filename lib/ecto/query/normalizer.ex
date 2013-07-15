defmodule Ecto.Query.Normalizer do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  def normalize(Query[] = query) do
    if query.select == nil and length(query.froms) == 1 do
      expr = { { :entity, :entity }, { :{}, [], [:entity, [], nil] } }
      QueryExpr[expr: expr, binding: [:entity]]
        |> query.select
    else
      query
    end
  end
end
