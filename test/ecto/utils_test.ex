defmodule Ecto.UtilsTest do
  use ExUnit.Case, async: true

  import Ecto.Utils

  test "app_dir/2" do
    assert app_dir(:ecto, "priv/migrations") ==
           Path.expand("../../_build/shared/lib/ecto/priv/migrations", __DIR__)

    assert_raise RuntimeError, "invalid application :unknown", fn ->
      app_dir(:unknown, "priv/migrations")
    end
  end
end
