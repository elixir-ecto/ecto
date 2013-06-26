defmodule Ecto.Query.FromBuilder do
  @moduledoc false

  def escape({ :in, _, [{ var, _, context}, {:__aliases__, _, _} = record] })
      when is_atom(var) and is_atom(context) do
    { var, record }
  end

  def escape(_other) do
    raise ArgumentError, message: "only `in` expressions binding variables to " <>
                                  "records allowed in from expressions"
  end
end
