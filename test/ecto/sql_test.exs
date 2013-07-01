Code.require_file "../test_helper.exs", __DIR__

defmodule Ecto.SQLTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.SQL

  test "from" do
    query = from(r in Repo) |> select([r], r.x)
    assert SQL.compile(query) == "SELECT r.x\nFROM repo AS r"

    query = from(r in Repo) |> from(r2 in Repo2) |> select([r], r.x)
    assert SQL.compile(query) == "SELECT r.x\nFROM repo AS r, repo2 AS r2"
  end

  test "select" do
    query = from(r in Repo) |> select([r], {r.x, r.y})
    assert SQL.compile(query) == "SELECT r.x, r.y\nFROM repo AS r"

    query = from(r in Repo) |> select([r], {r.x, r.y + r.z})
    assert SQL.compile(query) == "SELECT r.x, r.y + r.z\nFROM repo AS r"
  end

  test "where" do
    query = from(r in Repo) |> where([r], r.x != nil) |> select([r], r.x)
    assert SQL.compile(query) == "SELECT r.x\nFROM repo AS r\nWHERE (r.x != NULL)"

    query = from(r in Repo) |> where([r], r.x) |> where([r], r.y) |> select([r], r.x)
    assert SQL.compile(query) == "SELECT r.x\nFROM repo AS r\nWHERE (r.x) AND (r.y)"
  end

  test "variable binding" do
    x = 123
    query = from(r in Repo) |> select([], x)
    assert SQL.compile(query) == "SELECT 123\nFROM repo AS r"

    query = from(r in Repo) |> select([y], x + y.x)
    assert SQL.compile(query) == "SELECT 123 + y.x\nFROM repo AS r"
  end

  test "string escape" do
    x = "'\\ \n"
    query = from(r in Repo) |> select([], x)
    assert SQL.compile(query) == "SELECT '''\\\\ \n'\nFROM repo AS r"

    query = from(r in Repo) |> select([], "'\\")
    assert SQL.compile(query) == "SELECT '''\\\\'\nFROM repo AS r"
  end

  test "unary ops" do
    query = from(r in Repo) |> select([r], +r.x)
    assert SQL.compile(query) == "SELECT +r.x\nFROM repo AS r"

    query = from(r in Repo) |> select([r], -r.x)
    assert SQL.compile(query) == "SELECT -r.x\nFROM repo AS r"
  end

  test "binary ops" do
    query = from(r in Repo) |> select([], 1 == 2)
    assert SQL.compile(query) == "SELECT 1 = 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 != 2)
    assert SQL.compile(query) == "SELECT 1 != 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 <= 2)
    assert SQL.compile(query) == "SELECT 1 <= 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 >= 2)
    assert SQL.compile(query) == "SELECT 1 >= 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 < 2)
    assert SQL.compile(query) == "SELECT 1 < 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 > 2)
    assert SQL.compile(query) == "SELECT 1 > 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 + 2)
    assert SQL.compile(query) == "SELECT 1 + 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 - 2)
    assert SQL.compile(query) == "SELECT 1 - 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 * 2)
    assert SQL.compile(query) == "SELECT 1 * 2\nFROM repo AS r"

    query = from(r in Repo) |> select([], 1 / 2)
    assert SQL.compile(query) == "SELECT 1 / 2\nFROM repo AS r"
  end

  test "literals" do
    query = from(r in Repo) |> select([], :atom)
    assert SQL.compile(query) == "SELECT atom\nFROM repo AS r"

    query = from(r in Repo) |> select([], nil)
    assert SQL.compile(query) == "SELECT NULL\nFROM repo AS r"

    query = from(r in Repo) |> select([], true)
    assert SQL.compile(query) == "SELECT true\nFROM repo AS r"

    query = from(r in Repo) |> select([], false)
    assert SQL.compile(query) == "SELECT false\nFROM repo AS r"

    query = from(r in Repo) |> select([], "abc")
    assert SQL.compile(query) == "SELECT 'abc'\nFROM repo AS r"

    # TODO: Test more numbers
    query = from(r in Repo) |> select([], 123)
    assert SQL.compile(query) == "SELECT 123\nFROM repo AS r"
  end

  test "nested expressions" do
    z = 123
    query = from(r in Repo) |> select([x, y], x.a + (y.b + -z) - 3)
    assert SQL.compile(query) == "SELECT (x.a + (y.b + -123)) - 3\nFROM repo AS r"
  end
end
