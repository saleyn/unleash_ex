defmodule ConstraintBench do


  def test(arg = "NUM_EQ") do
    c =  mk_constraint(%{
        "contextName" => "userId",
        "operator" => "NUM_EQ",
        "value" => "123"
      })
    c1 =  mk_constraint(%{
        "contextName" => "userId",
        "operator" => "NUM_EQ",
        "value" => 123
      })
    x = 123
    y = 120
    f = fn x -> x == 123 end
    Benchee.run(%{
      arg => fn -> Unleash.Strategy.Constraint.check(y, arg, c) end,
      "numerical value" => fn -> Unleash.Strategy.Constraint.check(y, arg, c1) end,
      "fn x -> x == 120 end" => fn -> Unleash.Strategy.Constraint.check(y, f, c1) end,
      "x == y" => fn -> x == y end
      })
  end

  def test(arg = "IN") do
    list = 1..1_000 |> Enum.to_list()
    values = Enum.shuffle(list)
    y = 500
    c =  mk_constraint(%{
        "contextName" => "appName",
        "operator" => "IN",
        "values" => values
      })
    Benchee.run(%{
      arg => fn -> Unleash.Strategy.Constraint.check(y, arg, c) end,
      "value in values" => fn -> y in values end,
      "v:ordsets.is_element" => fn ->:ordsets.is_element(y, list) end
    })
  end

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


# c("benchmarks/constraint_bm.ex")

# ConstraintBench.test( "NUM_EQ")
