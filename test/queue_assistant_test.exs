defmodule MishkaInstaller.QueueAssistantTest do
  use ExUnit.Case, async: true
  alias MishkaInstaller.QueueAssistant

  test "new/0 is an empty queue" do
    assert QueueAssistant.empty?(QueueAssistant.new())
  end

  test "empty?/1 treats nil as empty" do
    assert QueueAssistant.empty?(nil)
  end

  test "insert/2 + out/1 preserve FIFO order" do
    queue =
      QueueAssistant.new()
      |> QueueAssistant.insert(:a)
      |> QueueAssistant.insert(:b)
      |> QueueAssistant.insert(:c)

    refute QueueAssistant.empty?(queue)

    {{:value, :a}, queue} = QueueAssistant.out(queue)
    {{:value, :b}, queue} = QueueAssistant.out(queue)
    {{:value, :c}, queue} = QueueAssistant.out(queue)
    assert QueueAssistant.empty?(queue)
  end

  test "out/1 on an empty queue returns :empty" do
    assert {:empty, _queue} = QueueAssistant.out(QueueAssistant.new())
  end
end
