defmodule Mix.Tasks.EctoTest do
  use ExUnit.Case, async: true

  import Mix.Tasks.Ecto

  defmodule Repo do
    def start_link do
      Process.get(:start_link)
    end

    def priv do
      "hello"
    end

    def __repo__ do
      true
    end
  end

  test :parse_repo do
    assert parse_repo([Repo]) == { Repo, [] }
    assert parse_repo([Repo, "foo"]) == { Repo, ["foo"] }
    assert parse_repo([inspect(Repo), "foo"]) == { Repo, ["foo"] }
    assert parse_repo([to_string(Repo), "foo"]) == { Repo, ["foo"] }
    assert_raise Mix.Error, fn -> parse_repo([]) end
    assert_raise Mix.Error, fn -> parse_repo([""]) end
  end

  test :ensure_repo do
    assert ensure_repo(Repo) == Repo
    assert_raise Mix.Error, fn -> parse_repo(String) end
    assert_raise Mix.Error, fn -> parse_repo(NotLoaded) end
  end

  test :ensure_started do
    Process.put(:start_link, :ok)
    assert ensure_started(Repo) == Repo

    Process.put(:start_link, { :ok, self })
    assert ensure_started(Repo) == Repo

    Process.put(:start_link, { :error, { :already_started, self } })
    assert ensure_started(Repo) == Repo

    Process.put(:start_link, { :error, self })
    assert_raise Mix.Error, fn -> ensure_started(Repo) end
  end

  test :migrations_path do
    assert migrations_path(Repo) == "hello/migrations"
    assert_raise Mix.Error, fn -> migrations_path(String) end
  end

  test :parse_strategy do
    assert parse_strategy([]) == { nil, [] }
    assert parse_strategy([to: 1]) == { {:to, 1}, [] }
    assert parse_strategy([step: 1]) == { {:step, 1}, [] }
    assert parse_strategy([all: true]) == { {:all, true}, [] }
    assert parse_strategy([foo: :bar]) == { nil, [foo: :bar] }
    assert parse_strategy([step: 1, foo: :bar]) == { {:step, 1}, [foo: :bar] }
    assert parse_strategy([all: true, step: 1]) == { {:step, 1}, [] }
    assert parse_strategy([all: true, to: 1]) == { {:to, 1}, [] }
    assert parse_strategy([step: 1, to: 1]) == { {:to, 1}, [] }
  end
end
