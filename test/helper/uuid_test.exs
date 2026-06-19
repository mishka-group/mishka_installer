defmodule MishkaInstaller.Helper.UUIDTest do
  use ExUnit.Case, async: true
  alias MishkaInstaller.Helper.UUID

  @uuid_v4 ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "generate/0 returns a 36-char lowercase version 4 UUID" do
    uuid = UUID.generate()
    assert byte_size(uuid) == 36
    assert Regex.match?(@uuid_v4, uuid)
    assert uuid == String.downcase(uuid)
  end

  test "generate/0 is (practically) unique" do
    uuids = for _ <- 1..1000, do: UUID.generate()
    assert length(Enum.uniq(uuids)) == 1000
  end

  test "bingenerate/0 returns 16 raw bytes with the v4 version/variant bits set" do
    <<_::48, version::4, _::12, variant::2, _::62>> = raw = UUID.bingenerate()
    assert byte_size(raw) == 16
    assert version == 4
    assert variant == 2
  end
end
