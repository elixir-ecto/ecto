defmodule Ecto.Migration.Manager do

  def start_link do
    Agent.start_link(fn -> HashDict.new end, name: __MODULE__)
  end

  def put_migration(migrator, runner) do
    Agent.update(__MODULE__,fn migrations -> Dict.put_new(migrations, migrator, runner) end)
  end

  def get_runner(migrator) do
    Agent.get(__MODULE__, fn migrations -> Dict.fetch!(migrations, migrator) end)
  end

  def drop_migration(migrator) do
    Agent.update(__MODULE__,fn migrations -> 
      Dict.delete(migrations, migrator) 
    end) 
  end

  def stop() do
    Agent.stop(__MODULE__)
  end 

end