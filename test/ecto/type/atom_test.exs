defmodule Ecto.Type.AtomTest do
  use ExUnit.Case

  describe "Ecto.Type.Atom else: default" do
    defmodule EctoTypeElseDefault do
      use Ecto.Type.Atom, values: [:foo, :bar, :baz]
    end

    test "correct type" do
      assert EctoTypeElseDefault.type() == :string
    end

    test "cast/1" do
      assert EctoTypeElseDefault.cast(:foo) == {:ok, :foo}
      assert EctoTypeElseDefault.cast("foo") == {:ok, :foo}
      assert EctoTypeElseDefault.cast(:other) == :error
    end

    test "load/1" do
      assert EctoTypeElseDefault.load("foo") == {:ok, :foo}
      assert EctoTypeElseDefault.load("bar") == {:ok, :bar}
      assert EctoTypeElseDefault.load("others") == :error
    end

    test "dump/1" do
      assert EctoTypeElseDefault.dump(:foo) == {:ok, "foo"}
      assert EctoTypeElseDefault.dump(:bar) == {:ok, "bar"}
      assert EctoTypeElseDefault.dump(:other) == :error
    end

    test "values/0" do
      assert EctoTypeElseDefault.values() == [:foo, :bar, :baz]
    end
  end

  describe "Ecto.Type.Atom else: :error" do
    defmodule EctoTypeElseError do
      use Ecto.Type.Atom, values: [:foo, :bar, :baz], else: :error
    end

    test "correct type" do
      assert EctoTypeElseError.type() == :string
    end

    test "cast/1" do
      assert EctoTypeElseError.cast(:foo) == {:ok, :foo}
      assert EctoTypeElseError.cast("foo") == {:ok, :foo}
      assert EctoTypeElseError.cast(:other) == :error
    end

    test "load/1" do
      assert EctoTypeElseError.load("foo") == {:ok, :foo}
      assert EctoTypeElseError.load("bar") == {:ok, :bar}
      assert EctoTypeElseError.load("others") == :error
    end

    test "dump/1" do
      assert EctoTypeElseError.dump(:foo) == {:ok, "foo"}
      assert EctoTypeElseError.dump(:bar) == {:ok, "bar"}
      assert EctoTypeElseError.dump(:other) == :error
    end

    test "values/0" do
      assert EctoTypeElseError.values() == [:foo, :bar, :baz]
    end
  end

  describe "Ecto.Type.Atom else: {:ok, :bad_value}" do
    defmodule EctoTypeElseBadValue do
      use Ecto.Type.Atom, values: [:foo, :bar, :baz], else: {:ok, :bad_value}
    end

    test "correct type" do
      assert EctoTypeElseBadValue.type() == :string
    end

    test "cast/1" do
      assert EctoTypeElseBadValue.cast(:foo) == {:ok, :foo}
      assert EctoTypeElseBadValue.cast("foo") == {:ok, :foo}
      assert EctoTypeElseBadValue.cast(:other) == :error
    end

    test "load/1" do
      assert EctoTypeElseBadValue.load("foo") == {:ok, :foo}
      assert EctoTypeElseBadValue.load("bar") == {:ok, :bar}
      assert EctoTypeElseBadValue.load("others") == {:ok, :bad_value}
    end

    test "dump/1" do
      assert EctoTypeElseBadValue.dump(:foo) == {:ok, "foo"}
      assert EctoTypeElseBadValue.dump(:bar) == {:ok, "bar"}
      assert EctoTypeElseBadValue.dump(:other) == :error
    end

    test "values/0" do
      assert EctoTypeElseBadValue.values() == [:foo, :bar, :baz]
    end
  end

  describe "Ecto.Type.Atom else: :transform" do
    defmodule EctoTypeElseTransform do
      use Ecto.Type.Atom, values: [:foo, :bar, :baz], else: :transform

      def transform("old_foo"), do: {:ok, :foo}
      def transform("old_bar"), do: {:ok, :bar}
      def transform("legacy_val"), do: {:ok, :legacy}
      def transform(_), do: :error
    end

    test "correct type" do
      assert EctoTypeElseTransform.type() == :string
    end

    test "cast/1" do
      assert EctoTypeElseTransform.cast(:foo) == {:ok, :foo}
      assert EctoTypeElseTransform.cast("foo") == {:ok, :foo}
      assert EctoTypeElseTransform.cast(:other) == :error
    end

    test "load/1" do
      assert EctoTypeElseTransform.load("foo") == {:ok, :foo}
      assert EctoTypeElseTransform.load("bar") == {:ok, :bar}

      assert EctoTypeElseTransform.load("old_foo") == {:ok, :foo}
      assert EctoTypeElseTransform.load("old_bar") == {:ok, :bar}
      assert EctoTypeElseTransform.load("legacy_val") == {:ok, :legacy}
      assert EctoTypeElseTransform.load("others") == :error
    end

    test "dump/1" do
      assert EctoTypeElseTransform.dump(:foo) == {:ok, "foo"}
      assert EctoTypeElseTransform.dump(:bar) == {:ok, "bar"}
      assert EctoTypeElseTransform.dump(:other) == :error
    end

    test "values/0" do
      assert EctoTypeElseTransform.values() == [:foo, :bar, :baz]
    end
  end
end
