defmodule Ecto.TypesTest do
  use ExUnit.Case, async: true

  import Kernel, except: [match?: 2], warn: false
  import Ecto.Types
  doctest Ecto.Types
end
