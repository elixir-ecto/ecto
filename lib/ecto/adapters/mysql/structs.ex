defmodule Ecto.Adapters.Mysql.Result do
  @type t :: %__MODULE__{
    command:  atom,
    columns:  [String.t] | nil,
    rows:     [tuple] | nil,
    num_rows: integer}

  defstruct [:command, :columns, :rows, :num_rows]
end

defmodule Ecto.Adapters.Mysql.OkPacket do
  @type t :: %__MODULE__{
    num_rows: integer,
    insert_id: integer,
    msg:  [String.t] | nil}

  defstruct [:num_rows, :insert_id, :msg]
end

defmodule Ecto.Adapters.Mysql.Error do
  @type t :: %__MODULE__{
    msg:  [String.t] | nil,
    query: [String.t] | nil,
    params: [list] | nil}

  defexception [:msg, :query, :params]

  def message(e) do
    e.msg || "no message"
  end
end
