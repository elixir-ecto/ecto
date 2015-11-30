defmodule Mix.Tasks.Ecto.LoadTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Load, only: [run: 0, run: 1]

  @tmp_path Path.join(tmp_path, inspect(Ecto.Dump))

  defmodule Adapter do
    def structure_load(_config, _structure), do: {:ok, 0}
    defmacro __before_compile__(_), do: :ok
  end

  defmodule BadAdapter do
    def structure_load(_config, _structure), do: {:error, 2}
    defmacro __before_compile__(_), do: :ok
  end

  defmodule Repo do
    def __repo__, do: true
    def __adapter__, do: Adapter

    def config do
      [priv: "tmp/#{inspect(Ecto.Load)}/repo", otp_app: :ecto]
    end
  end

  defmodule OtherRepo do
    def __repo__, do: true
    def __adapter__, do: Adapter

    def config do
      [priv: "tmp/#{inspect(Ecto.Load)}/other_repo", otp_app: :ecto]
    end
  end

  defmodule BadRepo do
    def __repo__, do: true
    def __adapter__, do: BadAdapter

    def config do
      [priv: "tmp/#{inspect(Ecto.Load)}/bad_repo", otp_app: :ecto]
    end
  end

  setup_all do
    Mix.Project.config()
    |> Keyword.get(:app)
    |> Application.put_env(:app_repo, Repo)

    on_exit fn ->
      Mix.Project.config()
      |> Keyword.get(:app)
      |> Application.delete_env(:app_repo)
    end

    :ok
  end

  test "raises no exception when run" do
    run()
  end

  test "raises no exception when run on a different repo" do
    run(["-r", to_string(OtherRepo)])
  end

  test "raises no exception when run on a different structure file" do
    filename = Path.join(@tmp_path, "repo/structure.sql")

    run(["-f", filename])
  end

  test "raises an exception when the structure loading fails" do
    assert_raise MatchError, fn ->
      run(["-r", to_string(BadRepo)])
    end
  end
end
