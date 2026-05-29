defmodule Mix.Tasks.Ecto.QueryTest do
  use ExUnit.Case

  alias Mix.Tasks.Ecto.Query

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field :text, :string
    end
  end

  defmodule Profile do
    use Ecto.Schema

    embedded_schema do
      field :bio, :string
      field :token, :string, redact: true
    end
  end

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      field :secret, :string, redact: true
      embeds_one :profile, Profile
      has_many :comments, Comment
    end
  end

  setup do
    Process.delete(:test_repo_all_results)
    Application.put_env(:ecto, :ecto_repos, [Ecto.TestRepo])
    :ok
  end

  test "runs a query against the repo in a read-only transaction" do
    Process.put(
      :test_repo_all_results,
      {2,
       [
         [1, "first", "hunter2", %{id: "profile-1", bio: "hello", token: "profile-token"}],
         [2, "second", "swordfish", %{id: "profile-2", bio: "world", token: "profile-secret"}]
       ]}
    )

    in_tmp("read_only", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      Query.run(["-r", "Ecto.TestRepo", "from(p in Post)"])

      assert_received {:transaction, _fun, opts}
      assert opts[:read_only]

      assert_received {:all, %Ecto.Query{}}
      assert_received {:mix_shell, :info, [output]}

      assert output =~ "%Mix.Tasks.Ecto.QueryTest.Post{"
      assert output =~ ~s(title: "first")
      assert output =~ "%Mix.Tasks.Ecto.QueryTest.Profile{"
      assert output =~ ~s(bio: "hello")
      refute output =~ "__meta__"
      refute output =~ "comments:"
      refute output =~ "secret:"
      refute output =~ "hunter2"
      refute output =~ "token:"
      refute output =~ "profile-token"
    end)
  end

  test "uses the configured default repo" do
    Process.put(:test_repo_all_results, {1, [[1, "first", "hunter2", nil]]})

    in_tmp("default_repo", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      Query.run(["from(p in Post)"])

      assert_received {:transaction, _fun, opts}
      assert opts[:read_only]
    end)
  end

  test "accepts a schema module queryable" do
    Process.put(:test_repo_all_results, {1, [[1, "first", "hunter2", nil]]})

    Query.run(["-r", "Ecto.TestRepo", inspect(Post)])

    assert_received {:all, %Ecto.Query{}}
    assert_received {:mix_shell, :info, [output]}
    assert output =~ ~s(title: "first")
  end

  test "limits printed entries" do
    Process.put(
      :test_repo_all_results,
      {2, [[1, "first", "hunter2", nil], [2, "second", "swordfish", nil]]}
    )

    in_tmp("limit", fn ->
      File.write!(".iex.exs", "alias #{inspect(Post)}\n")

      Query.run(["-r", "Ecto.TestRepo", "--limit", "1", "from(p in Post)"])

      assert_received {:mix_shell, :info, [output]}
      assert output =~ ~s(title: "first")
      refute output =~ ~s(title: "second")
    end)
  end

  test "raises when the evaluated expression is not queryable" do
    for query <- ["1", "%{}", "[]", ":ok"] do
      assert_raise Mix.Error,
                   ~r/Expected ecto\.query to evaluate to a queryable expression, got:/,
                   fn ->
                     Query.run(["-r", "Ecto.TestRepo", query])
                   end
    end
  end

  test "raises when multiple repos are given" do
    assert_raise Mix.Error,
                 "ecto.query found multiple repositories, please pass one with -r",
                 fn ->
                   Query.run(["-r", "Ecto.TestRepo", "-r", "Ecto.TestRepo", "from(p in Post)"])
                 end
  end

  test "raises when a query is not given" do
    assert_raise Mix.Error, "ecto.query expects a query to be given", fn ->
      Query.run(["-r", "Ecto.TestRepo"])
    end
  end

  @tmp_path Path.expand("../../../tmp", __DIR__)

  defp in_tmp(path, fun) do
    path = Path.join(@tmp_path, path)
    File.rm_rf!(path)
    File.mkdir_p!(path)
    File.cd!(path, fun)
  end
end
