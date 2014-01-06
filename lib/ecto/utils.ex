defmodule Ecto.Utils do
  @moduledoc """
  Convenience functions used throughout Ecto and
  imported into users modules.
  """

  @doc """
  Receives an `app` and returns the absolute `path` from
  the application directory.
  """
  @spec app_dir(atom, String.t) :: String.t | { :error, term }
  def app_dir(app, path) when is_atom(app) and is_binary(path) do
    case :code.lib_dir(app) do
      { :error, _ } = error -> error
      lib when is_list(lib) -> Path.join(String.from_char_list!(lib), path)
    end
  end

  @doc """
  An implementation of the command callback that
  is shared across different shells.
  
  Copied straight from https://github.com/elixir-lang/elixir/blob/v0.12.1/lib/mix/lib/mix/shell.e
  """
  def cmd(command, callback) do
    port = Port.open({ :spawn, shell_command(command) },
      [:stream, :binary, :exit_status, :hide, :use_stdio, :stderr_to_stdout])
    do_cmd(port, callback)
  end

  defp do_cmd(port, callback) do
    receive do
      { ^port, { :data, data } } ->
        callback.(data)
        do_cmd(port, callback)
      { ^port, { :exit_status, status } } ->
        status
    end
  end

  # Finding shell command logic from :os.cmd in OTP
  # https://github.com/erlang/otp/blob/8deb96fb1d017307e22d2ab88968b9ef9f1b71d0/lib/kernel/src/os.erl#L184
  defp shell_command(command) do
    case :os.type do
      { :unix, _ } ->
        command = command
          |> String.replace("\"", "\\\"")
          |> :binary.bin_to_list
        'sh -c "' ++ command ++ '"'

      { :win32, osname } ->
        command = :binary.bin_to_list(command)
        case { System.get_env("COMSPEC"), osname } do
          { nil, :windows } -> 'command.com /c ' ++ command
          { nil, _ } -> 'cmd /c ' ++ command
          { cmd, _ } -> '#{cmd} /c ' ++ command
        end
    end
  end
end
