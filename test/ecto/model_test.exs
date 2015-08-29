defmodule Ecto.ModelTest do
  use ExUnit.Case, async: true

  test "complains when a schema is not defined" do
    assert_raise RuntimeError, ~r"does not define a schema", fn ->
      defmodule Sample do
        use Ecto.Model
      end
    end
  end
end
