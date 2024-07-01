defmodule MishkaInstaller.Installer.Collect do
  @moduledoc false
  # Based on
  # https://elixir-lang.slack.com/archives/C03EPRA3B/p1719319847338759?thread_ts=1719318192.858049&cid=C03EPRA3B
  defstruct [:callback, acc: nil]

  defimpl Collectable do
    alias MishkaInstaller.Installer.Collect

    def into(%Collect{acc: acc, callback: callback}) do
      collector_fun = fn
        acc, {:cont, elem} -> callback.(elem, acc)
        acc, :done -> acc
        _acc, :halt -> :ok
      end

      {acc, collector_fun}
    end
  end
end
