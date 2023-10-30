defmodule Ecto.Query.FilterModelTest do
  use ExUnit.Case, async: true
  alias Ecto.Query.FilterModel

  defmodule System do
    use Ecto.Schema

    schema "systems" do
      field :name, :string
      field :years_in_service, :integer
    end
  end

  defmodule User do
    use Ecto.Schema

    schema "users" do
      field :role, Ecto.Enum, values: [admin: "admin", auditor: "auditor", user: "user"]
      field :level, Ecto.Enum, values: [tier_1: 1, tier_2: 2]
      field :username, :string
      field :years_employed, :integer
      has_many :systems, System
    end
  end

  test "blank case" do
    assert %{from: %{source: {"users", _}}, wheres: []} = FilterModel.derive(User, %{})
  end

  test "nil and :any" do
    filter_model = %{
      role: :any,
      level: nil
    }

    assert %{
             wheres: [
               %{expr: {:is_nil, [], _}},
               %{expr: {:not, [], [{:is_nil, [], _}]}}
             ]
           } = FilterModel.derive(User, filter_model)
  end

  test "parameterized value mappings" do
    filter_model = %{
      role: [:admin],
      level: [:tier_1]
    }

    assert %{
             wheres: [
               %{expr: {:in, _, _}, params: [{[1], _}]},
               %{expr: {:in, _, _}, params: [{["admin"], _}]}
             ]
           } = FilterModel.derive(User, filter_model)
  end

  test "gte/lte filters" do
    filter_model = %{
      years_employed: %{gte: 5, lte: 10}
    }

    assert %{
             from: %{source: {"users", _}},
             wheres: [
               %{op: :and, expr: {:>=, [], _}, params: [{5, {0, :years_employed}}]},
               %{op: :and, expr: {:<=, [], _}, params: [{10, {0, :years_employed}}]}
             ]
           } = FilterModel.derive(User, filter_model)
  end

  test "ilike filter" do
    input = "John%"

    filter_model = %{
      username: %{ilike: input}
    }

    assert %{
             wheres: [%{expr: {:ilike, _, _}, params: [{^input, :string}]}]
           } = FilterModel.derive(User, filter_model)
  end

  test "derive unions multiple models" do
    filter_models = [
      %{
        role: [:admin, :auditor]
      },
      %{
        level: [:tier_1]
      },
      %{
        systems: [
          %{
            years_in_service: %{gte: 5}
          }
        ]
      }
    ]

    assert %{
             from: %{source: {"users", _}},
             combinations: [
               {:union, %{from: %{source: {"users", _}}, joins: []}},
               {:union,
                %{
                  from: %{source: {"users", _}},
                  joins: [
                    %{
                      qual: :inner,
                      source: %{
                        query: %{from: %{source: {"systems", _}}}
                      }
                    }
                  ]
                }}
             ]
           } = FilterModel.derive(User, filter_models)
  end
end
