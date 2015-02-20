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
  end
end

defmodule Ecto.CastError do
  @moduledoc """
  Raised at runtime when a value cannot be cast.
  """
  defexception [:model, :field, :type, :value, :message]

  def exception(opts) do
    model = Keyword.fetch!(opts, :model)
    field = Keyword.fetch!(opts, :field)
    value = Keyword.fetch!(opts, :value)
    type  = Keyword.fetch!(opts, :type)
    msg   = Keyword.fetch!(opts, :message)
    %__MODULE__{model: model, field: field, value: value, type: type, message: msg}
  end
end

defmodule Ecto.InvalidURLError do
  defexception [:message, :url]

  def exception(opts) do
    url = Keyword.fetch!(opts, :url)
    msg = Keyword.fetch!(opts, :message)
    msg = "invalid url #{url}, #{msg}"
    %__MODULE__{message: msg, url: url}
  end
end

defmodule Ecto.NoPrimaryKeyError do
  defexception [:message, :model]

  def exception(opts) do
    model   = Keyword.fetch!(opts, :model)
    message = "model `#{inspect model}` has no primary key"
    %__MODULE__{message: message, model: model}
  end
end

defmodule Ecto.MissingPrimaryKeyError do
  defexception [:message, :struct]

  def exception(opts) do
    struct  = Keyword.fetch!(opts, :struct)
    message = "struct `#{inspect struct}` is missing primary key value"
    %__MODULE__{message: message, struct: struct}
  end
end


defmodule Ecto.ChangeError do
  defexception [:message]
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

defmodule Ecto.MigrationError do
  defexception [:message]
end

defmodule Ecto.StaleModelError do
  defexception [:message]

  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    model = Keyword.fetch!(opts, :model)

    msg = """
    attempted to #{action} a stale model:

    #{inspect model}
    """

    %__MODULE__{message: msg}
  end
end
