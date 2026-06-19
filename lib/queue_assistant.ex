defmodule MishkaInstaller.QueueAssistant do
  @moduledoc """
  A thin FIFO queue wrapper over the Erlang [`:queue`](https://www.erlang.org/doc/man/queue) module.

  It is used to serialise background work (event compilation, library installation) so that only
  one job runs at a time.

  ```elixir
  alias MishkaInstaller.QueueAssistant

  {{:value, item}, queue} =
    QueueAssistant.new()
    |> QueueAssistant.insert(:job)
    |> QueueAssistant.out()
  ```
  """

  @typedoc "An Erlang queue."
  @type t :: :queue.queue(any())

  @doc """
  Returns a new empty queue.
  """
  @spec new() :: t()
  def new(), do: :queue.new()

  @doc """
  Inserts `item` at the rear of `queue` and returns the new queue.
  """
  @spec insert(t(), any()) :: t()
  def insert(queue, item), do: :queue.in(item, queue)

  @doc """
  Removes the item at the front of `queue`.

  Returns `{{:value, item}, queue}` or `{:empty, queue}` when the queue is empty.
  """
  @spec out(t()) :: {{:value, any()}, t()} | {:empty, t()}
  def out(queue), do: :queue.out(queue)

  @doc """
  Returns `true` if `queue` is empty (or `nil`).
  """
  @spec empty?(t() | nil) :: boolean()
  def empty?(nil), do: true
  def empty?(queue), do: :queue.is_empty(queue)
end
