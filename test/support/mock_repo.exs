defmodule Ecto.MockAdapter do
  @behaviour Ecto.Adapter

  defmacro __using__(_opts), do: :ok
  def start_link(_repo, _opts), do: :ok
  def stop(_repo), do: :ok

  ## Queryable

  def all(_repo, _query, _params, _opts), do: [[1]]
  def update_all(_repo, _query, _values, _params, _opts), do: 1
  def delete_all(_repo, _query, _params, _opts), do: 1

  ## Model

  def insert(_repo, _source, _fields, [_], _opts),
    do: {:ok, {1}}
  def update(_repo, _source, _filter, _fields, [_], _opts),
    do: {:ok, {1}}
  def delete(_repo, _source, _filter, _opts),
    do: :ok

  ## Transactions

  def transaction(_repo, _opts, fun) do
    # Makes transactions "trackable" in tests
    send self, {:transaction, fun}
    {:ok, fun.()}
  end

  ## Migrations

  def execute_migration(_repo, command) do
    Process.put(:last_command, command)
    :ok
  end

  def object_exists?(_repo, object) do
    Process.put(:last_exists, object)
    true
  end

  def migrated_versions(_repo) do
    Process.get(:migrated_versions) || []
  end

  def insert_migration_version(repo, version) do
    Process.put(:migrated_versions, [version|migrated_versions(repo)])
  end

  def delete_migration_version(repo, version) do
    Process.put(:migrated_versions, List.delete(migrated_versions(repo), version))
  end
end

defmodule Ecto.MockRepo do
  use Ecto.Repo, adapter: Ecto.MockAdapter, otp_app: :ecto
end
