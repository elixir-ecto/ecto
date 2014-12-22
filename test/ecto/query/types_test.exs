defmodule Ecto.Query.TypesTest do
  use ExUnit.Case, async: true

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Query.Types
  doctest Ecto.Query.Types
end
