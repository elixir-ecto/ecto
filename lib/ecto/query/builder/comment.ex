import Kernel, except: [apply: 2]

defmodule Ecto.Query.Builder.Comment do
  @moduledoc false

  alias Ecto.Query.Builder

  @spec escape(Macro.t(), Macro.Env.t()) :: Macro.t()
  def escape(comment, _env) when is_binary(comment), do: validate(comment)
  def escape(comment, _env) when is_atom(comment), do: Atom.to_string(comment)

  def escape(comment, _env),
    do: raise(ArgumentError, "comment must be a compile time string, got: #{inspect(comment)}")

  def build(query, comment, _opts, %Macro.Env{} = env) do
    Builder.apply_query(query, __MODULE__, [escape(comment, env)], env)
  end

  @doc """
  The callback applied by `build/4` to build the query.
  """
  @spec apply(Ecto.Queryable.t(), String.t()) :: Ecto.Query.t()
  def apply(%Ecto.Query{comments: comments} = query, comment) do
    %{query | comments: comments ++ [comment]}
  end

  def apply(query, comment) do
    apply(Ecto.Queryable.to_query(query), comment)
  end

  defp validate(comment) when is_binary(comment) do
    if String.contains?(comment, "*/") do
      raise ArgumentError, "comment must not contain a closing */ character"
    end

    comment
  end
end
