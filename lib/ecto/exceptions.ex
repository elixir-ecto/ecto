alias Ecto.Query.Util

defmodule Ecto.QueryError do
  defexception [:reason, :type, :query, :file, :line]

  def message(e) do
    if e.type && e.query && e.file && e.line do
      file = Path.relative_to_cwd(e.file)
      """
      #{Exception.format_file_line(file, e.line)} the query:

          #{inspect e.query}

      is invalid: #{e.reason}
      """
    else
      e.reason
    end
  end
end

defmodule Ecto.InvalidURL do
  defexception [:message, :url]

  def exception(opts) do
    msg = "invalid url #{opts[:url]}, #{opts[:reason]}"
    %Ecto.InvalidURL{message: msg, url: opts[:url]}
  end
end

defmodule Ecto.NoPrimaryKey do
  defexception [:message, :model]

  def exception(opts) do
    msg = "model `#{opts[:model]}` has no primary key"
    %Ecto.NoPrimaryKey{message: msg, model: opts[:model]}
  end
end

defmodule Ecto.InvalidModel do
  defexception [:model, :field, :type, :expected_type, :reason]

  def message(e) do
    expected_type = Util.type_to_ast(e.expected_type) |> Macro.to_string
    type          = Util.type_to_ast(e.type)          |> Macro.to_string

    "model #{inspect e.model} failed validation when #{e.reason}, " <>
    "field #{e.field} had type #{type} but type #{expected_type} was expected"
  end
end

defmodule Ecto.NotSingleResult do
  defexception [:message, :model, :primary_key, :id, :results]

  def exception(opts) do
    msg = "the result set from `#{opts[:model]}` " <>
          "where `#{opts[:primary_key]} == #{opts[:id]}` " <>
          "was not a single value"

    struct(Ecto.NotSingleResult, [message: msg] ++ opts)
  end
end

defmodule Ecto.Query.TypeCheckError do
  defexception [:expr, :types, :allowed, :type, :query, :file, :line]

  @moduledoc """
  Exception raised when a query does not type check.
  Read `Ecto.Query` and `Ecto.Query.API` docs for more information.
  """

  def message(e) do
    if e.type && e.query && e.file && e.line do
      file = Path.relative_to_cwd(e.file)
      msg = """
      #{Exception.format_file_line(file, e.line)} the query:

          #{e.type}: #{Macro.to_string(e.query)}

      has an expression that does not type check:
      """
    else
      msg = "the following expression does not type check:"
    end

    {name, _, _} = e.expr
    expected = Enum.map_join(e.allowed, "\n    ", &Macro.to_string(&1))

    types  = Enum.map(e.types, &Util.type_to_ast/1)
    actual = Macro.to_string({name, [], types})

    """
    #{msg}

        #{Macro.to_string(e.expr)}

    Allowed types for #{name}/#{length(e.types)}:

        #{expected}

    Got: #{actual}
    """
  end
end

defmodule Ecto.AssociationNotLoadedError do
  defexception [:message, :type, :name, :owner]

  def exception(opts) do
    msg = "the #{opts[:type]} association on #{opts[:owner]}.#{opts[:name]} was not loaded"

    struct(Ecto.AssociationNotLoadedError, [message: msg] ++ opts)
  end
end

defmodule Ecto.MigrationError do
  defexception [:message]
end
