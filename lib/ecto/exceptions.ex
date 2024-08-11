defmodule Ecto.Query.CompileError do
  @moduledoc """
  Raised at compilation time when the query cannot be compiled.
  """
  defexception [:message]
end

defmodule Ecto.Query.CastError do
  @moduledoc """
  Raised at runtime when a value cannot be cast.
  """
  defexception [:type, :value, :message]

  def exception(opts) do
    value = Keyword.fetch!(opts, :value)
    type = Keyword.fetch!(opts, :type)
    msg = Keyword.fetch!(opts, :message)
    %__MODULE__{value: value, type: type, message: msg}
  end
end

defmodule Ecto.QueryError do
  @moduledoc """
  Raised at runtime when the query is invalid.
  """
  defexception [:message]

  def exception(opts) do
    message = Keyword.fetch!(opts, :message)
    query = Keyword.fetch!(opts, :query)
    hint = Keyword.get(opts, :hint)

    message = """
    #{message} in query:

    #{Inspect.Ecto.Query.to_string(query)}
    """

    file = opts[:file]
    line = opts[:line]

    message =
      if file && line do
        relative = Path.relative_to_cwd(file)
        Exception.format_file_line(relative, line) <> " " <> message
      else
        message
      end

    message =
      if hint do
        message <> "\n" <> hint <> "\n"
      else
        message
      end

    %__MODULE__{message: message}
  end
end

defmodule Ecto.SubQueryError do
  @moduledoc """
  Raised at runtime when a subquery is invalid.
  """
  defexception [:message, :exception]

  def exception(opts) do
    exception = Keyword.fetch!(opts, :exception)
    query = Keyword.fetch!(opts, :query)

    message = """
    the following exception happened when compiling a subquery.

        #{Exception.format(:error, exception, []) |> String.replace("\n", "\n    ")}

    The subquery originated from the following query:

    #{Inspect.Ecto.Query.to_string(query)}
    """

    %__MODULE__{message: message, exception: exception}
  end
end

defmodule Ecto.InvalidChangesetError do
  @moduledoc """
  Raised when we cannot perform an action because the
  changeset is invalid.
  """
  defexception [:action, :changeset]

  def message(%{action: action, changeset: changeset}) do
    changes = extract_changes(changeset)
    errors = Ecto.Changeset.traverse_errors(changeset, & &1)

    """
    could not perform #{action} because changeset is invalid.

    Errors

    #{pretty(errors)}

    Applied changes

    #{pretty(changes)}

    Params

    #{pretty(changeset.params)}

    Changeset

    #{pretty(changeset)}
    """
  end

  defp pretty(term) do
    inspect(term, pretty: true)
    |> String.split("\n")
    |> Enum.map_join("\n", &("    " <> &1))
  end

  defp extract_changes(%Ecto.Changeset{changes: changes}) do
    Enum.reduce(changes, %{}, fn {key, value}, acc ->
      case value do
        %Ecto.Changeset{action: :delete} -> acc
        _ -> Map.put(acc, key, extract_changes(value))
      end
    end)
  end

  defp extract_changes([%Ecto.Changeset{action: :delete} | tail]),
    do: extract_changes(tail)

  defp extract_changes([%Ecto.Changeset{} = changeset | tail]),
    do: [extract_changes(changeset) | extract_changes(tail)]

  defp extract_changes(other),
    do: other
end

defmodule Ecto.CastError do
  @moduledoc """
  Raised when a changeset can't cast a value.
  """
  defexception [:message, :type, :value]

  def exception(opts) do
    type = Keyword.fetch!(opts, :type)
    value = Keyword.fetch!(opts, :value)
    msg = opts[:message] || "cannot cast #{inspect(value)} to #{Ecto.Type.format(type)}"
    %__MODULE__{message: msg, type: type, value: value}
  end
end

defmodule Ecto.InvalidURLError do
  defexception [:message, :url]

  def exception(opts) do
    url = Keyword.fetch!(opts, :url)
    msg = Keyword.fetch!(opts, :message)
    msg = "invalid URL #{url}, #{msg}. The parsed URL is: #{inspect(URI.parse(url))}"
    %__MODULE__{message: msg, url: url}
  end
end

defmodule Ecto.NoPrimaryKeyFieldError do
  @moduledoc """
  Raised at runtime when an operation that requires a primary key is invoked
  with a schema that does not define a primary key by using `@primary_key false`
  """
  defexception [:message, :schema]

  def exception(opts) do
    schema = Keyword.fetch!(opts, :schema)
    message = "schema `#{inspect(schema)}` has no primary key"
    %__MODULE__{message: message, schema: schema}
  end
end

defmodule Ecto.NoPrimaryKeyValueError do
  @moduledoc """
  Raised at runtime when an operation that requires a primary key is invoked
  with a schema missing value for its primary key
  """
  defexception [:message, :struct]

  def exception(opts) do
    struct = Keyword.fetch!(opts, :struct)
    message = "struct `#{inspect(struct)}` is missing primary key value"
    %__MODULE__{message: message, struct: struct}
  end
end

defmodule Ecto.ChangeError do
  defexception [:message]
end

defmodule Ecto.NoResultsError do
  defexception [:message]

  def exception(opts) do
    query = Keyword.fetch!(opts, :queryable) |> Ecto.Queryable.to_query()

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
    query = Keyword.fetch!(opts, :queryable) |> Ecto.Queryable.to_query()
    count = Keyword.fetch!(opts, :count)

    msg = """
    expected at most one result but got #{count} in query:

    #{Inspect.Ecto.Query.to_string(query)}
    """

    %__MODULE__{message: msg}
  end
end

defmodule Ecto.MultiplePrimaryKeyError do
  defexception [:message]

  def exception(opts) do
    operation = Keyword.fetch!(opts, :operation)
    source = Keyword.fetch!(opts, :source)
    params = Keyword.fetch!(opts, :params)
    count = Keyword.fetch!(opts, :count)

    msg = """
    expected #{operation} on #{source} to return at most one entry but got #{count} entries.

    This typically means the field(s) set as primary_key in your schema/source
    are not enough to uniquely identify entries in the repository.

    Those are the parameters sent to the repository:

    #{inspect(params)}
    """

    %__MODULE__{message: msg}
  end
end

defmodule Ecto.MigrationError do
  defexception [:message]
end

defmodule Ecto.StaleEntryError do
  defexception [:message, :changeset]

  def exception(opts) do
    action = Keyword.fetch!(opts, :action)
    changeset = Keyword.fetch!(opts, :changeset)

    msg = """
    attempted to #{action} a stale struct:

    #{inspect(changeset.data)}

    This typically happens when the struct no longer exists in the database \
    or a database trigger/rule has forbidden the action. If stale entries are \
    expected, you may use `:stale_error_field` to convert this into a changeset \
    error, or set `:allow_stale` to true if you would like stale operations to \
    be considered a success (such as a stale deletion)
    """

    %__MODULE__{message: msg, changeset: changeset}
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
            Enum.map_join(
              constraints,
              "\n",
              &"    * #{inspect(&1.constraint)} (#{&1.type}_constraint)"
            )
      end

    msg = """
    constraint error when attempting to #{action} struct:

        * #{inspect(constraint)} (#{type}_constraint)

    If you would like to stop this constraint violation from raising an
    exception and instead add it as an error to your changeset, please
    call `#{type}_constraint/3` on your changeset with the constraint
    `:name` as an option.

    #{constraints}
    """

    %__MODULE__{message: msg, type: type, constraint: constraint}
  end
end
