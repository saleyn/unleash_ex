defmodule Unleash.Strategy.ConstraintTest do
  use ExUnit.Case

  alias Unleash.Strategy.Constraint

  describe "IN and NOT_IN constraints" do
    test "it returns true if there is no constraints" do
      assert true == Constraint.verify_all([], %{})
    end

    test "it returns false if there is no context" do
      assert false == Constraint.verify_all([mk_constraint()], %{})
    end

    test "IN positive test" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "appName",
                     "operator" => "IN",
                     "values" => ["unleash"]
                   })
                 ],
                 %{app_name: "unleash"}
               )
    end

    test "IN positive test inverted" do
      assert false ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "appName",
                     "operator" => "IN",
                     "values" => ["unleash"],
                     "inverted" => true
                   })
                 ],
                 %{app_name: "unleash"}
               )
    end

    test "NOT_IN negative test" do
      assert false ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "appName",
                     "operator" => "NOT_IN",
                     "values" => ["unleash"]
                   })
                 ],
                 %{app_name: "unleash"}
               )
    end

    test "NOT_IN positive test" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "appName",
                     "operator" => "NOT_IN",
                     "values" => ["not_unleash"]
                   })
                 ],
                 %{app_name: "unleash"}
               )
    end
  end

  describe "DATE_AFTER and DATE_BEFORE constraints" do
    test "DATE_AFTER positive test" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_AFTER",
                     "value" => "2025-05-15T12:10:00.000Z"
                   })
                 ],
                 %{app_name: "unleash", current_time: "2025-06-16T12:10:00.000Z"}
               )
    end

    test "DATE_AFTER positive test :now" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_AFTER",
                     "value" => "2025-05-15T12:10:00.000Z"
                   })
                 ],
                 %{app_name: "unleash", current_time: :now}
               )
    end

    test "DATE_AFTER negative test" do
      assert false ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_AFTER",
                     "value" => "2025-05-15T12:10:00.000Z"
                   })
                 ],
                 %{app_name: "unleash", current_time: "2025-04-16T12:10:00.000Z"}
               )
    end

    test "DATE_BEFORE positive test" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_BEFORE",
                     "value" => "2025-05-15T12:10:00.000Z"
                   })
                 ],
                 %{app_name: "unleash", current_time: "2025-04-16T12:10:00.000Z"}
               )
    end

    test "DATE_BEFORE negapositivetive test" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_BEFORE",
                     "value" => "2025-05-15T12:10:00.000Z"
                   })
                 ],
                 %{app_name: "unleash", current_time: "2024-05-15T12:10:00.000Z"}
               )
    end

    test "DATE_BEFORE negative test" do
      assert false ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_BEFORE",
                     "value" => "2025-05-15T12:10:00.000Z"
                   })
                 ],
                 %{app_name: "unleash", current_time: "2025-05-15T12:10:00.000Z"}
               )
    end

    test "DATE_BEFORE negative test inverted" do
      assert true ==
               Constraint.verify_all(
                 [
                   mk_constraint(%{
                     "contextName" => "currentTime",
                     "operator" => "DATE_BEFORE",
                     "value" => "2025-05-15T12:10:00.000Z",
                     "inverted" => true
                   })
                 ],
                 %{app_name: "unleash", current_time: "2025-05-15T12:10:00.000Z"}
               )
    end
  end

  defp mk_constraint(), do: mk_constraint(%{})

  defp mk_constraint(map) do
    %{
      "caseInsensitive" => Map.get(map, "caseInsensitive", false),
      "contextName" => Map.get(map, "contextName", ""),
      "inverted" => Map.get(map, "inverted", false),
      "operator" => Map.get(map, "operator", ""),
      "value" => Map.get(map, "value", ""),
      "values" => Map.get(map, "values", [])
    }
  end
end
