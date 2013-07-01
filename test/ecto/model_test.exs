Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.ModelTest do
  use ExUnit.Case, async: true

  defmodule MyModel do
    use Ecto.Model
    table_name :my_model

    primary_key
    field :name, :string, default: "eric"
    field :email, :string, uniq: true
  end

  test "metadata" do
    fields = [
      { :id, :integer, [primary_key: true, autoinc: true, uniq: true] },
      { :name, :string, [default: "eric"] },
      { :email, :string, [uniq: true] }
    ]

    assert MyModel.__ecto__(:table) == :my_model
    assert MyModel.__ecto__(:fields) == fields
    assert MyModel.__record__(:fields) ==
           [id: nil, name: "eric", email: nil]
  end
end
