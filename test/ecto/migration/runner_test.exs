defmodule Ecto.Migration.RunnerTest do
  use ExUnit.Case, async: false

  alias Ecto.Migration.Runner
  alias Ecto.Migration.Table
  alias Ecto.Migration.Index

  defmodule MockAdapter do
    def execute_migration(_repo, command) do
      {:migrated, command}
    end

    def object_exists?(_repo, {:column, {:products, :name}}), do: true
    def object_exists?(_repo, _), do: false
  end

  defmodule MockRepo do
    def adapter do
      MockAdapter
    end
  end

  setup do
    {:ok, _} = Runner.start_link(MockRepo)
    :ok
  end

  test "run in forward direction" do
    Runner.direction(:forward)

    assert Runner.execute({:create, %Table{}, []}) == {:migrated, {:create, %Table{}, []}}
    assert Runner.execute({:create, %Index{}}) == {:migrated, {:create, %Index{}}}
    assert Runner.execute({:drop, %Table{}}) == {:migrated, {:drop, %Table{}}}
    assert Runner.execute({:drop, %Index{}}) == {:migrated, {:drop, %Index{}}}
    assert Runner.execute({:alter, %Table{}, []}) == {:migrated, {:alter, %Table{}, []}}
  end

  test "run in reverse direction" do
    Runner.direction(:reverse)

    assert Runner.execute({:create, %Table{}, []}) == {:migrated, {:drop, %Table{}}}
    assert Runner.execute({:create, %Index{}}) == {:migrated, {:drop, %Index{}}}
    assert Runner.execute({:alter, %Table{}, []}) == {:migrated, {:alter, %Table{}, []}}
  end

  test "cannot reverse drop table" do
    Runner.direction(:reverse)

    assert_raise Ecto.MigrationError, fn ->
      Runner.execute({:drop, %Table{}})
    end
  end

  test "cannot reverse drop index" do
    Runner.direction(:reverse)

    assert_raise Ecto.MigrationError, fn ->
      Runner.execute({:drop, %Index{}})
    end
  end

  test "can reverse column additions to removals" do
    Runner.direction(:reverse)

    assert Runner.execute({:alter, %Table{}, [{:add, :summary, :string, []}]}) == {:migrated, {:alter, %Table{}, [{:remove, :summary}] }}
  end

  test "can reverse column renaming" do
    Runner.direction(:reverse)

    assert Runner.execute({:alter, %Table{}, [{:rename, :summary, :details}]}) == {:migrated, {:alter, %Table{}, [{:rename, :details, :summary}]}}
  end

  test "cannot reverse column removal" do
    Runner.direction(:reverse)

    assert_raise Ecto.MigrationError, fn ->
      Runner.execute({:alter, %Table{}, [{:remove, :summary}]})
    end
  end

  test "cannot reverse column modification" do
    Runner.direction(:reverse)

    assert_raise Ecto.MigrationError, fn ->
      Runner.execute({:alter, %Table{}, [{:modify, :summary, :string, []}]})
    end
  end

  test "column exists" do
    assert Runner.exists?(:column, {:products, :name}) == true
    assert Runner.exists?(:column, {:products, :title}) == false
  end

  test "column exists in reverse" do
    Runner.direction(:reverse)

    assert Runner.exists?(:column, {:products, :name}) == false
    assert Runner.exists?(:column, {:products, :title}) == true
  end
end
