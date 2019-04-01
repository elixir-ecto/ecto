defmodule Ecto.Repo.RegistryTest do
  use ExUnit.Case, async: true

  import Ecto.Repo.Registry

  test "lookup by repo_name_or_pid option" do
    repo_name = :tenant_db
    pid = Process.whereis(repo_name)
    assert {adapter, adapter_meta} = lookup(Ecto.TestRepo, [repo_name_or_pid: repo_name])
    assert {^adapter, ^adapter_meta} = lookup(Ecto.TestRepo, [repo_name_or_pid: pid])
    assert_raise RuntimeError, ~r"could not lookup :other because it was not started or it does not exist", fn ->
      lookup(Ecto.TestRepo, [repo_name_or_pid: :other])
    end
  end
end
