defmodule Ecto.Migration.Manager do

  def start_link do
    Agent.start_link(fn -> HashDict.new end, name: __MODULE__)
  end

  def put_migration(migrator, prefix) do
    Agent.update(__MODULE__,fn migrations -> Dict.put_new(migrations, migrator, {nil, prefix}) end)
  end

  def put_runner(migrator, runner) do
    Agent.update(__MODULE__,fn migrations -> 
      Dict.update!(migrations, migrator, fn({_, prefix}) -> {runner, prefix} end)
    end)
  end

  def put_prefix(migrator, prefix) do
    Agent.update(__MODULE__,fn migrations -> 
      Dict.update!(migrations, migrator, fn({runner, _}) -> {runner, prefix} end)
    end)
  end

  def get_runner(migrator) do
    {runner, _prefix} = Agent.get(__MODULE__, fn migrations -> Dict.fetch!(migrations, migrator) end)
    runner
  end

  def get_prefix(migrator) do
    {_runner, prefix} = Agent.get(__MODULE__, fn migrations -> Dict.fetch!(migrations, migrator) end)
    prefix
  end

  def drop_migration(migrator) do
    Agent.update(__MODULE__,fn migrations -> 
      Dict.delete(migrations, migrator) 
    end) 
    check_empty()
  end

  def stop() do
    Agent.stop(__MODULE__)
  end 

  def check_empty() do
    migrations = Agent.get(__MODULE__, fn migrations -> migrations end)
    if Dict.size(migrations) == 0 do
      stop()
    end
  end

end