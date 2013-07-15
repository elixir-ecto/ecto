defmodule Ecto.Query.Normalizer do
  @moduledoc false

  alias Ecto.Query.Query
  alias Ecto.Query.QueryExpr

  def normalize(Query[] = query) do
    if query.select == nil and length(query.froms) == 1 do
      expr = { { :entity, :"$$0" }, { :{}, [], [:"$$0", [], nil] } }
      QueryExpr[expr: expr, binding: [:"$$0"]]
        |> query.select
    else
      query
    end
  end
end
