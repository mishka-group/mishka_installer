defmodule MishkaInstaller.ProductionReleaseTest do
  use ExUnit.Case, async: false

  # A real `mix release` build plus two cold boots — slow, so excluded by default.
  # Run with: mix test --only production_release
  @moduletag :production_release
  @moduletag timeout: 600_000

  test "an installed app survives a cold mix-release restart (replayed from volume + Mnesia)" do
    script = Path.join([__DIR__, "integration", "production_release", "run.sh"])
    {out, status} = System.cmd("bash", [script], stderr_to_stdout: true)
    assert status == 0, "release restart test failed:\n#{out}"
    assert out =~ "PASS: installed app survived a cold release restart"
  end
end
