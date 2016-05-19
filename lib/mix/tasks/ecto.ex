defmodule Mix.Tasks.Ecto do
  use Mix.Task

  @shortdoc "Prints Ecto help information"

  @moduledoc """
  Prints Ecto tasks and their information.

      mix ecto

  """

  @doc false
  def run(args) do
    {_opts, args, _} = OptionParser.parse(args)

    case args do
      [] -> general()
      _ ->
        Mix.raise "Invalid arguments, expected: mix ecto"
    end
  end

  defp general() do
    Application.ensure_all_started(:ecto)
    Mix.shell.info "Ecto v#{Application.spec(:ecto, :vsn)}"
    Mix.shell.info "A database wrapper and language integrated query for Elixir."
    Mix.shell.info "\nAvailable tasks:\n"
    Mix.Tasks.Help.run(["--search", "ecto."])
  end
end
