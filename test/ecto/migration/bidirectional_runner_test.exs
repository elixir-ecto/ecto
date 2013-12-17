defmodule Ecto.Migration.BidirectionalRunnerTest do
  use ExUnit.Case, async: false

  alias Ecto.Migration.BidirectionalRunner
  alias Ecto.Migration.Ast.Table
  alias Ecto.Migration.Ast.Index

  setup_all do
    {:ok, pid} = BidirectionalRunner.start_link
    {:ok, pid: pid}
  end

  teardown_all context do
    :erlang.exit(context[:pid], :kill)
    :ok
  end

  test "run in forward direction" do
    BidirectionalRunner.direction(:up)

    assert BidirectionalRunner.run({:create, Table.new, []}) == {:create, Table.new, []}
    assert BidirectionalRunner.run({:create, Index.new}) == {:create, Index.new}
    assert BidirectionalRunner.run({:drop, Table.new}) == {:drop, Table.new}
    assert BidirectionalRunner.run({:drop, Index.new}) == {:drop, Index.new}
    assert BidirectionalRunner.run({:alter, Table.new, []}) == {:alter, Table.new, []}
  end

  test "run in reverse direction" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:create, Table.new, []}) == {:drop, Table.new}
    assert BidirectionalRunner.run({:create, Index.new}) == {:drop, Index.new}
    assert BidirectionalRunner.run({:alter, Table.new, []}) == {:alter, Table.new, []}
  end

  test "cannot reverse drop table" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:drop, Table.new}) == :not_reversable
  end

  test "cannot reverse drop index" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:drop, Index.new}) == :not_reversable
  end

  test "can reverse column additions to removals" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:alter, Table.new, [{:add, :summary, :string, []}]}) == {:alter, Table.new, [{:remove, :summary}] }
  end

  test "can reverse column renaming" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:alter, Table.new, [{:rename, :summary, :details}]}) == {:alter, Table.new, [{:rename, :details, :summary}]}
  end

  test "cannot reverse column removal" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:alter, Table.new, [{:remove, :summary}]}) == :not_reversable
  end

  test "cannot reverse column modification" do
    BidirectionalRunner.direction(:down)

    assert BidirectionalRunner.run({:alter, Table.new, [{:modify, :summary, :string, []}]}) == :not_reversable
  end
end
