defmodule Ecto.Model.ValidationsTest do
  use ExUnit.Case, async: true
  import Support.EvalHelpers

  defmodule User do
    use Ecto.Model.Validations

    defstruct [:name, :age, :filename]

    validate user,
          name: present(),
           age: present(),
          also: validate_attachments

    validatep validate_attachments(user),
      filename: present()
  end

  defmodule Custom do
    use Ecto.Model.Validations

    validate validate(user, range, validate_name),
          name: present() when validate_name,
           age: member_of(range)
  end

  test "defines the given validations" do
    assert User.validate(%User{}) ==
      %{name: ["can't be blank"],
        age: ["can't be blank"],
        filename: ["can't be blank"]}
  end

  test "supports custom validations with arguments" do
    user = %User{age: 27}

    assert Custom.validate(user, 30..60, false) ==
           %{age: ["is not included in the list"]}

    assert Custom.validate(user, 20..60, true) ==
           %{name: ["can't be blank"]}
  end

  test "raises on functions with no arguments" do
    msg = "validate and validatep expects a function with at least one argument"
    assert_raise ArgumentError, msg, fn ->
      quote_and_eval do
        defmodule Sample do
          use Ecto.Model.Validations
          validate validate(), name: present()
        end
      end
    end
  end

  test "raises when there is no var" do
    msg = "validate and validatep expects a function with a var as first argument, got: :oops"
    assert_raise ArgumentError, msg, fn ->
      quote_and_eval do
        defmodule Sample do
          use Ecto.Model.Validations
          validate validate(:oops), name: present()
        end
      end
    end
  end
end
