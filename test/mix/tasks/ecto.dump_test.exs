defmodule Mix.Tasks.Ecto.DumpTest do
  use ExUnit.Case

  import Support.FileHelpers
  import Mix.Tasks.Ecto.Dump, only: [run: 0, run: 1]

  @tmp_path Path.join(tmp_path, inspect(Ecto.Dump))

  defmodule Adapter do
    def structure_dump(_config) do
      {"--dump--", 0}
    end
    defmacro __before_compile__(_), do: :ok
    def database_info, do: %{type: "foobar", version: "1.0"}
  end

  Application.put_env(:ecto, __MODULE__.Repo, [])

  defmodule Repo do
    def __repo__ do
      true
    end

    def __adapter__ do
      Adapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Dump)}/repo", otp_app: :ecto]
    end
  end

  defmodule OtherRepo do
    def __repo__ do
      true
    end

    def __adapter__ do
      Adapter
    end

    def config do
      [priv: "tmp/#{inspect(Ecto.Dump)}/other_repo", otp_app: :ecto]
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

  test "dumps the structure" do
    run()

    filename = Path.join(@tmp_path, "repo/structure.sql")

    assert_file filename, fn file ->
      assert file =~ "--dump--"
    end
  end

  test "dumps the structure of a non-default repo" do
    run(["-r", to_string(OtherRepo)])

    filename = Path.join(@tmp_path, "other_repo/structure.sql")

    assert_file filename, fn file ->
      assert file =~ "--dump--"
    end
  end

  test "dumps the structure to a specified file" do
    run(["-f", Path.join(@tmp_path, "my_structure.sql")])

    filename = Path.join(@tmp_path, "my_structure.sql")

    assert_file filename, fn file ->
      assert file =~ "--dump--"
    end
  end
end
