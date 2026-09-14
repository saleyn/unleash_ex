defmodule Unleash.FeatureCompiler do
  @moduledoc """
  Compiles feature flags into a dynamically-generated BEAM module at poll time.

  Instead of interpreting strategy/constraint maps on every `enabled?` call
  (ETS copy → strategy dispatch → constraint iteration → anonymous fn calls),
  this module generates `Unleash.CompiledFeatures` with named function clauses
  per feature. The BEAM JIT can inline named function calls, eliminating the
  overhead of closure dispatch, and all constants (params, parsed constraint
  values, strategy modules) are embedded as literals in the bytecode.

  The generated module exposes:
  - `enabled?(feature_name, context)` → `boolean() | nil` (nil = not found)
  - `feature(feature_name)` → `%Feature{} | nil`
  """

  alias Unleash.Config
  alias Unleash.Feature
  alias Unleash.Strategy.Constraint

  @compiled_module Unleash.CompiledFeatures

  @doc """
  Compiles all features into a generated module `Unleash.CompiledFeatures`.
  Called from `Unleash.Repo` after each successful features poll.
  """
  @spec compile_all([Feature.t()]) :: :ok
  def compile_all(features) do
    module_ast = generate_module(features)

    # soft_purge avoids killing processes still executing in the old module;
    # if any process is mid-call it simply no-ops and :code.delete will
    # move current → old safely (BEAM allows calling old code).
    :code.soft_purge(@compiled_module)
    :code.delete(@compiled_module)

    Module.create(@compiled_module, module_ast, Macro.Env.location(__ENV__))

    # Store feature structs in persistent_term for get_variant access
    Enum.each(features, fn f ->
      :persistent_term.put({:unleash_feature, f.name}, f)
    end)

    :persistent_term.put(:unleash_compiled_names, Enum.map(features, & &1.name))
    :persistent_term.put(:unleash_features_compiled, true)
    :ok
  end

  @doc """
  Removes persistent_term entries for features that no longer exist.
  """
  @spec cleanup([Feature.t()]) :: :ok
  def cleanup(features) do
    current_names = MapSet.new(features, & &1.name)
    old_names = :persistent_term.get(:unleash_compiled_names, [])

    Enum.each(old_names, fn name ->
      unless MapSet.member?(current_names, name) do
        :persistent_term.erase({:unleash_feature, name})
      end
    end)

    :ok
  end

  @doc """
  Returns the feature struct, or nil if not found.
  """
  @spec get_feature(String.t()) :: Feature.t() | nil
  def get_feature(name) when is_binary(name) do
    :persistent_term.get({:unleash_feature, name}, nil)
  end

  def get_feature(name) when is_atom(name), do: get_feature(Atom.to_string(name))

  @doc """
  Checks if the compiled module is loaded and available.
  Uses a persistent_term flag set by compile_all/1 to avoid
  the code server round-trip of Code.ensure_loaded?/1.
  """
  @spec compiled?() :: boolean()
  def compiled? do
    :persistent_term.get(:unleash_features_compiled, false)
  end

  # -- AST generation --

  defp generate_module(features) do
    enabled_clauses = Enum.flat_map(features, &generate_enabled_clause/1)
    enabled_fallback = generate_enabled_fallback()

    # Generate private constraint-checking functions for features that have them
    constraint_fns = Enum.flat_map(features, &generate_constraint_fns/1)

    # find_value helper
    find_value_fns = generate_find_value()

    quote do
      @moduledoc false

      unquote_splicing(enabled_clauses)
      unquote(enabled_fallback)

      unquote_splicing(constraint_fns)
      unquote_splicing(find_value_fns)
    end
  end

  defp generate_enabled_clause(%Feature{enabled: false, name: name}) do
    [
      quote do
        def enabled?(unquote(name), _context), do: false
      end
    ]
  end

  defp generate_enabled_clause(%Feature{enabled: true, strategies: [], name: name}) do
    [
      quote do
        def enabled?(unquote(name), _context), do: true
      end
    ]
  end

  defp generate_enabled_clause(%Feature{enabled: true, strategies: strategies, name: name}) do
    strategy_checks = generate_strategy_checks(strategies, name)

    [
      quote do
        def enabled?(unquote(name), context) do
          unquote(strategy_checks)
        end
      end
    ]
  end

  defp generate_enabled_fallback do
    quote do
      def enabled?(_, _context), do: nil
    end
  end

  # Generate OR-chain of strategy checks with short-circuit
  defp generate_strategy_checks(strategies, feature_name) do
    checks =
      strategies
      |> Enum.with_index()
      |> Enum.map(fn {strategy, idx} ->
        generate_single_strategy_check(strategy, feature_name, idx)
      end)

    # OR them together: check1 or check2 or ...
    Enum.reduce(checks, quote(do: false), fn check, acc ->
      quote do: unquote(acc) or unquote(check)
    end)
  end

  defp generate_single_strategy_check(strategy, feature_name, idx) do
    strat_name = strategy["name"]
    module = Map.fetch!(Config.strategies_map(), strat_name)
    params = strategy["parameters"] || %{}
    constraints = strategy["constraints"] || []

    # Pre-parse rollout to integer for FlexibleRollout
    params = maybe_parse_rollout(params)

    constraint_check =
      if constraints == [] do
        quote(do: true)
      else
        fn_name = constraint_fn_name(feature_name, idx)
        quote do: unquote(fn_name)(context)
      end

    strategy_check =
      quote do
        Unleash.Strategy.normalize_enabled(
          unquote(module).enabled?(unquote(Macro.escape(params)), context)
        )
      end

    quote do
      unquote(constraint_check) and unquote(strategy_check)
    end
  end

  # Generate private defp for constraint checking
  defp generate_constraint_fns(%Feature{enabled: true, strategies: strategies, name: name}) do
    strategies
    |> Enum.with_index()
    |> Enum.flat_map(fn {strategy, idx} ->
      constraints = strategy["constraints"] || []

      if constraints == [] do
        []
      else
        generate_constraint_fn(constraints, name, idx)
      end
    end)
  end

  defp generate_constraint_fns(_), do: []

  defp generate_constraint_fn(constraints, feature_name, strat_idx) do
    fn_name = constraint_fn_name(feature_name, strat_idx)

    # Precompute all constraints (parse NUM/SEMVER/DATE values, resolve context atoms)
    precomputed = Enum.map(constraints, &Constraint.precompute/1)

    # Generate inline checks for each constraint
    checks =
      Enum.map(precomputed, fn constraint ->
        generate_single_constraint_check(constraint)
      end)

    # AND them all together
    body =
      Enum.reduce(checks, quote(do: true), fn check, acc ->
        quote do: unquote(acc) and unquote(check)
      end)

    [
      quote do
        defp unquote(fn_name)(context) do
          unquote(body)
        end
      end
    ]
  end

  defp generate_single_constraint_check(constraint) do
    name = constraint["contextName"]
    name_atom = constraint["contextNameAtom"] || String.to_atom(Recase.to_snake(name))
    op = constraint["operator"]
    inverted = constraint["inverted"] || false

    check_ast = generate_op_check(op, constraint, name, name_atom)

    if inverted do
      quote do: not unquote(check_ast)
    else
      check_ast
    end
  end

  defp generate_op_check("IN", %{"values" => values}, name, name_atom) do
    quote do
      find_value(context, unquote(name), unquote(name_atom)) in unquote(values)
    end
  end

  defp generate_op_check("NOT_IN", %{"values" => values}, name, name_atom) do
    quote do
      find_value(context, unquote(name), unquote(name_atom)) not in unquote(values)
    end
  end

  defp generate_op_check("STR_CONTAINS", %{"values" => values}, name, name_atom) do
    quote do
      case find_value(context, unquote(name), unquote(name_atom)) do
        nil -> false
        val -> String.contains?(val, unquote(values))
      end
    end
  end

  defp generate_op_check("STR_STARTS_WITH", %{"values" => values}, name, name_atom) do
    quote do
      case find_value(context, unquote(name), unquote(name_atom)) do
        nil -> false
        val -> String.starts_with?(val, unquote(values))
      end
    end
  end

  defp generate_op_check("STR_ENDS_WITH", %{"values" => values}, name, name_atom) do
    quote do
      case find_value(context, unquote(name), unquote(name_atom)) do
        nil -> false
        val -> String.ends_with?(val, unquote(values))
      end
    end
  end

  defp generate_op_check("NUM_EQ", %{"value" => parsed_value}, name, name_atom) do
    generate_num_check(name, name_atom, parsed_value, :==)
  end

  defp generate_op_check("NUM_GT", %{"value" => parsed_value}, name, name_atom) do
    generate_num_check(name, name_atom, parsed_value, :>)
  end

  defp generate_op_check("NUM_GTE", %{"value" => parsed_value}, name, name_atom) do
    generate_num_check(name, name_atom, parsed_value, :>=)
  end

  defp generate_op_check("NUM_LT", %{"value" => parsed_value}, name, name_atom) do
    generate_num_check(name, name_atom, parsed_value, :<)
  end

  defp generate_op_check("NUM_LTE", %{"value" => parsed_value}, name, name_atom) do
    generate_num_check(name, name_atom, parsed_value, :<=)
  end

  # Fallback: use the full Constraint.verify_all for unsupported operators
  defp generate_op_check(_op, constraint, _name, _name_atom) do
    escaped = Macro.escape(constraint)

    quote do
      Unleash.Strategy.Constraint.verify_all([unquote(escaped)], context)
    end
  end

  defp generate_num_check(name, name_atom, parsed_value, op) when is_number(parsed_value) do
    quote do
      case find_value(context, unquote(name), unquote(name_atom)) do
        nil ->
          false

        val ->
          case Unleash.Strategy.Constraint.to_number(val) do
            :error -> false
            n -> unquote(op)(n, unquote(parsed_value))
          end
      end
    end
  end

  # Value failed to parse at compile time → always false
  defp generate_num_check(_name, _name_atom, :error, _op) do
    quote do: false
  end

  # Value is still a string (shouldn't happen after precompute, but handle gracefully)
  defp generate_num_check(name, name_atom, value, op) when is_binary(value) do
    case Constraint.to_number(value) do
      :error -> quote(do: false)
      parsed -> generate_num_check(name, name_atom, parsed, op)
    end
  end

  defp generate_find_value do
    [
      quote do
        defp find_value(nil, _name, _name_atom), do: nil

        defp find_value(ctx, name, name_atom) do
          Map.get(
            ctx,
            name_atom,
            find_value(Map.get(ctx, :properties), name, name_atom)
          )
        end
      end
    ]
  end

  defp constraint_fn_name(feature_name, strat_idx) do
    # Create a deterministic atom for the constraint checker function
    safe_name =
      feature_name
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.downcase()

    String.to_atom("check_constraints_#{safe_name}_#{strat_idx}")
  end

  defp maybe_parse_rollout(%{"rollout" => rollout} = params) when is_binary(rollout) do
    case Integer.parse(rollout, 10) do
      {n, _} -> %{params | "rollout" => n}
      _ -> params
    end
  end

  defp maybe_parse_rollout(params), do: params
end
