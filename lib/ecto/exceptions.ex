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

defmodule Ecto.InvalidChangesetError do
  @moduledoc """
  Raised when we cannot perform an action because the
  changeset is invalid.
  """
  defexception [:action, :changeset]

  def message(%{action: action, changeset: changeset}) do
    """
    could not perform #{action} because changeset is invalid.

    * Changeset changes

    #{inspect changeset.changes}

    * Changeset params

    #{inspect changeset.params}

    * Changeset errors

    #{inspect changeset.errors}
    """
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

defmodule Ecto.NoPrimaryKeyFieldError do
  @moduledoc """
  Raised at runtime when an operation that requires a primary key is invoked
  with a model that does not define a primary key by using `@primary_key false`
  """
  defexception [:message, :model]

  def exception(opts) do
    model   = Keyword.fetch!(opts, :model)
    message = "model `#{inspect model}` has no primary key"
    %__MODULE__{message: message, model: model}
  end
end

defmodule Ecto.NoPrimaryKeyValueError do
  @moduledoc """
  Raised at runtime when an operation that requires a primary key is invoked
  with a model missing value for it's primary key
  """
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

defmodule Ecto.ConstraintError do
  defexception [:type, :constraint, :message]

  def exception(opts) do
    type = Keyword.fetch!(opts, :type)
    constraint = Keyword.fetch!(opts, :constraint)
    changeset = Keyword.fetch!(opts, :changeset)
    action = Keyword.fetch!(opts, :action)

    constraints =
      case changeset.constraints do
        [] ->
          "The changeset has not defined any constraint."
        constraints ->
          "The changeset defined the following constraints:\n\n" <>
            Enum.map_join(constraints, "\n", &"    * #{&1.type}: #{&1.constraint}")
      end

    msg = """
    constraint error when attempting to #{action} model:

        * #{type}: #{constraint}

    If you would like to convert this constraint into an error, please
    call #{type}_constraint/3 in your changeset and define the proper
    constraint name. #{constraints}
    """

    %__MODULE__{message: msg, type: type, constraint: constraint}
  end
end

defmodule Ecto.UnmachedRelationError do
  defexception [:message]

  def exception(opts) do
    old_value = Keyword.fetch!(opts, :old_value)
    new_value = Keyword.fetch!(opts, :new_value)

    msg =
      case Keyword.fetch!(opts, :cardinality) do
        :one  -> "attempted to update model with:"
        :many -> "attempted to update one of the models with:"
      end

    msg = """
    #{msg}

    #{inspect new_value}

    but could not find matching key in:

    #{inspect old_value}
    """
    %__MODULE__{message: msg}
  end
end
