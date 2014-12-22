alias Ecto.Query.Util

# TODO: They should all finish with Error
# TODO: Test NoResultsError and MultipleResultsError with unit tests

defmodule Ecto.Query.CompileError do
  @moduledoc """
  Raised at compilation time when the query cannot be compiled.
  """
  defexception [:message]
end

defmodule Ecto.QueryError do
  @moduledoc """
  Raised at runtime when the query is invalid.
  """
  defexception [:message]

  def exception(opts) do
    message = Keyword.fetch!(opts, :message)
    query   = Keyword.fetch!(opts, :query)
    message = """
    #{message} in query:

    #{Inspect.Ecto.Query.to_string(query)}
    """

    if (file = opts[:file]) && (line = opts[:line]) do
      relative = Path.relative_to_cwd(file)
      message  = Exception.format_file_line(relative, line) <> " " <> message
    end

    %__MODULE__{message: message}
  rescue
    e ->
      IO.inspect System.stacktrace
      reraise e, System.stacktrace
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

defmodule Ecto.NoResultsError do
  defexception [:message]

  def exception(opts) do
    query = Keyword.fetch!(opts, :queryable) |> Ecto.Queryable.to_query

    msg = """
    expected at least one result but got none in query:

    #{Inspect.Ecto.Query.to_string(query)}
    """

    %__MODULE__{message: msg}
  end
end

defmodule Ecto.MultipleResultsError do
  defexception [:message]

  def exception(opts) do
    query = Keyword.fetch!(opts, :queryable) |> Ecto.Queryable.to_query
    count = Keyword.fetch!(opts, :count)

    msg = """
    expected at most one result but got #{count} in query:

    #{Inspect.Ecto.Query.to_string(query)}
    """

    %__MODULE__{message: msg}
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
