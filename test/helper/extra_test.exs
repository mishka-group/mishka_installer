defmodule MishkaInstaller.Helper.ExtraTest do
  use ExUnit.Case, async: true
  alias MishkaInstaller.Helper.Extra

  test "get_unix_time/0 returns the current unix time in seconds" do
    now = DateTime.utc_now() |> DateTime.to_unix()
    assert_in_delta Extra.get_unix_time(), now, 2
  end

  test "randstring/1 returns an uppercase alphanumeric string of the requested length" do
    str = Extra.randstring(16)
    assert String.length(str) == 16
    assert str == String.upcase(str)
    assert Regex.match?(~r/\A[0-9A-Z]+\z/, str)
    assert Extra.randstring(0) == ""
  end

  test "erlang_result/1 maps selectors to match-spec result bodies" do
    assert Extra.erlang_result(:all) == [:"$_"]
    assert Extra.erlang_result(:selected) == [:"$$"]
    assert Extra.erlang_result([:"$1"]) == [:"$1"]
  end

  describe "erlang_fields/4" do
    test "places numbered match vars for selected fields and wildcards elsewhere" do
      assert Extra.erlang_fields({Person}, [:id, :name, :age], [:name], 1) ==
               {Person, :_, :"$1", :_}
    end

    test "numbers multiple selected fields in order" do
      assert Extra.erlang_fields({Person}, [:id, :name, :age], [:id, :age], 1) ==
               {Person, :"$1", :_, :"$2"}
    end

    test "all wildcards when nothing is selected" do
      assert Extra.erlang_fields({Person}, [:id, :name], [], 1) == {Person, :_, :_}
    end
  end
end
