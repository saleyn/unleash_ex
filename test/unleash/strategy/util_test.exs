defmodule Unleash.Strategy.UtilsTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Unleash.Strategy.Utils

  describe "normalize" do
    test "returns the correct normalized number" do
      assert 73 = Utils.normalize("123", "gr1")
      assert 25 = Utils.normalize("999", "groupX")
    end
  end

  describe "in_list?" do
    property "returns true if the member is in the list" do
      check all list <- list_of(string(:alphanumeric), min_length: 1),
                member <- member_of(list),
                string_list = Enum.join(list, ",") do
        assert Utils.in_list?(string_list, member)
      end
    end

    property "returns false if the member is not in the list" do
      check all list <- list_of(string(:alphanumeric), min_length: 1),
                member <- string(:alphanumeric),
                member not in list,
                string_list = Enum.join(list, ",") do
        refute Utils.in_list?(string_list, member)
      end
    end

    property "runs the transformation function on members in the list" do
      check all list <- list_of(string(:alphanumeric), min_length: 1),
                member <- member_of(list),
                member = String.upcase(member),
                string_list = Enum.join(list, ",") do
        assert Utils.in_list?(string_list, member, &String.upcase/1)
      end
    end

    test "bad inputs return false" do
      refute Utils.in_list?(nil, nil, nil)
    end
  end

  describe "parse_int" do
    property "returns integers as-is" do
      check all x <- integer() do
        assert ^x = Utils.parse_int(x)
      end
    end

    property "parses integers with strings" do
      check all {i, x} <- map(positive_integer(), fn j -> {j, Integer.to_string(j)} end) do
        assert ^i = Utils.parse_int(x)
      end
    end

    property "returns 0 if given negative numbers" do
      check all i <- positive_integer(),
                i = i * -1,
                x = Integer.to_string(i) do
        assert 0 = Utils.parse_int(x)
      end
    end

    property "returns 0 if given non-numbers" do
      check all x <- string([?a..?z, ?A..?Z]) do
        assert 0 = Utils.parse_int(x)
      end
    end
  end
end
