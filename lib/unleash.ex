defmodule Unleash do
  @moduledoc """
  If you have no plans on extending the client, then `Unleash` will be the main
  usage point of the library. Upon starting your app, the client is registered
  with the unleash server, and two `GenServer`s are started, one to fetch and
  poll for feature flags from the server, and one to send metrics.

  Configuring `:disable_client` to `true` disables both servers as well as
  registration, while configuring `:disable_metrics` to `true` disables only
  the metrics `GenServer`.
  """

  use Application

  alias Unleash.Config
  alias Unleash.Feature
  alias Unleash.Metrics
  alias Unleash.Repo
  alias Unleash.Variant

  require Logger

  @typedoc """
  The context needed for a few activation strategies. Check their documentation
  for the required key.

  * `:user_id` is the ID of the user interacting _with your system_, can be any
    `String.t()`
  * `session_id` is the ID of the current session _in your system_, can be any
    `String.t()`
  * `remote_address` is the address of the user interacting _with your system_,
    can be any `String.t()`
  """
  @type context :: %{
          user_id: String.t(),
          session_id: String.t(),
          remote_address: String.t()
        }

  @doc """
  Aliased to `enabled?/2`
  """
  @spec is_enabled?(atom() | String.t(), boolean) :: boolean
  def is_enabled?(feature, default) when is_boolean(default),
    do: enabled?(feature, default)

  @doc """
  Aliased to `enabled?/3`
  """
  @spec is_enabled?(atom() | String.t(), map(), boolean) :: boolean
  def is_enabled?(feature, context \\ %{}, default \\ false),
    do: enabled?(feature, context, default)

  @doc """
  Checks if the given feature is enabled. Checks as though an empty context was
  passed in.

  ## Examples

      iex> Unleash.enabled?(:my_feature, false)
      false

      iex> Unleash.enabled?(:my_feature, true)
      true
  """
  @spec enabled?(atom() | String.t(), boolean) :: boolean
  def enabled?(feature, default) when is_boolean(default),
    do: enabled?(feature, %{}, default)

  @doc """
  Checks if the given feature is enabled.

  If `:disable_client` is `true`, simply returns the given `default`.

  If `:disable_metrics` is `true`, nothing is logged about the given toggle.

  ## Examples

      iex> Unleash.enabled?(:my_feature)
      false

      iex> Unleash.enabled?(:my_feature, context)
      false

      iex> Unleash.enabled?(:my_feature, context, true)
      false
  """
  @spec enabled?(atom() | String.t(), map(), boolean) :: boolean
  def enabled?(feature, context \\ %{}, default \\ false) do
    start_metadata = Unleash.Client.telemetry_metadata(%{feature: feature, context: context})

    :telemetry.span(
      [:unleash, :feature, :enabled?],
      start_metadata,
      fn ->
        {result, metadata} =
          if Config.disable_client() do
            {default, %{reason: :disabled_client}}
          else
            feature
            |> Repo.get_feature()
            |> case do
              nil ->
                {default, %{reason: :feature_not_found}}

              feature ->
                {result, strategy_evaluations} =
                  Feature.enabled?(feature, Map.put(context, :feature_toggle, feature.name))

                Metrics.add_metric({feature, result})

                metadata = %{
                  reason: :strategy_evaluations,
                  strategy_evaluations: strategy_evaluations,
                  feature_enabled: feature.enabled
                }

                {result, metadata}
            end
          end

        telemetry_metadata =
          start_metadata
          |> Map.merge(metadata)
          |> Map.put(:result, result)

        {result, telemetry_metadata}
      end
    )
  end

  @doc """
  Returns a variant for the given name.

  If `:disable_client` is `true`, returns the fallback.

  A [variant](https://unleash.github.io/docs/beta_features#feature-toggle-variants)
  allows for more complicated toggling than a simple `true`/`false`, instead
  returning one of the configured variants depending on whether or not there
  are any overrides for a given context value as well as factoring in the
  weights for the various weight options.

  ## Examples

      iex> Unleash.get_variant(:test)
      %{enabled: true, name: "test", payload: %{...}}

      iex> Unleash.get_variant(:test)
      %{enabled: false, name: "disabled"}
  """
  @spec get_variant(atom() | String.t(), map(), Variant.result()) :: Variant.result()
  def get_variant(name, context \\ %{}, fallback \\ Variant.disabled()) do
    start_metadata = Unleash.Client.telemetry_metadata(%{variant: name, context: context})

    :telemetry.span(
      [:unleash, :variant, :get],
      start_metadata,
      fn ->
        {result, metadata} =
          if Config.disable_client() do
            {fallback, %{reason: :disabled_client}}
          else
            name
            |> Repo.get_feature()
            |> case do
              nil ->
                {fallback, %{reason: :feature_not_found}}

              feature ->
                Variant.select_variant(feature, context)
            end
          end

        {result, Map.merge(start_metadata, metadata)}
      end
    )
  end

  @doc false
  def start(_type, _args) do
    # Configure httpc to disable keep-alive connections
    configure_httpc()

    :persistent_term.put(Config.persisten_term_key(), false)

    children =
      [
        {Repo, Config.disable_client()},
        {{Metrics, name: Metrics}, Config.disable_client() or Config.disable_metrics()}
      ]
      |> Enum.filter(fn {_m, not_enabled} -> not not_enabled end)
      |> Enum.map(fn {module, _e} -> module end)

    if children != [] do
      spawn(fn ->
        do_registration(
          Config.registration_attempts(),
          0,
          Config.registration_attempts_interval()
        )
      end)
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  def do_registration(n, n, _) do
    Logger.error("Failed to register unleash client after #{n} attempts")
  end

  def do_registration(n, m, interval) do
    case Config.client().register_client() do
      {:ok, _} ->
        Logger.info("uleash client was registered after #{m + 1} attempts")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to register unleash client: #{reason}")
        :timer.sleep(interval)
        do_registration(n, m + 1, interval)
    end
  end

  defp configure_httpc do
    # Ensure inets/httpc is started
    :application.ensure_all_started(:inets)

    # Disable keep-alive connections
    :httpc.set_options([
      {:max_sessions, 0},          # No session reuse
      {:max_keep_alive_length, 0}, # No keep-alive connections
      {:keep_alive_timeout, 0},    # No keep-alive timeout
      {:max_pipeline_length, 0}    # Disable HTTP pipelining
    ])

    # Start monitor to kill hanging httpc:handle_answer/3 processes (if enabled)
    if Config.httpc_monitor_enabled() do
      start_httpc_monitor()
      Logger.info("httpc configured with keep-alive disabled and process monitor started")
    else
      Logger.info("httpc configured with keep-alive disabled (process monitor disabled)")
    end
  end

  def start_httpc_monitor do
    spawn_link(fn -> httpc_monitor_loop(%{}) end)
  end

  defp httpc_monitor_loop(process_tracker) do
    # Check at configured interval for hanging httpc processes
    Process.sleep(Config.httpc_monitor_interval())

    # Track and kill httpc:handle_answer/3 processes that hang too long
    updated_tracker = monitor_and_kill_hanging_processes(process_tracker)

    httpc_monitor_loop(updated_tracker)
  end

  defp monitor_and_kill_hanging_processes(process_tracker) do
    current_time = System.monotonic_time(:millisecond)
    kill_timeout = Config.httpc_kill_timeout()

    # Find all httpc handle_answer processes
    httpc_processes =
      Process.list()
      |> Enum.filter(&httpc_handle_answer_process?/1)

    # Update tracker with new processes
    updated_tracker =
      Enum.reduce(httpc_processes, process_tracker, fn pid, tracker ->
        Map.put_new(tracker, pid, current_time)
      end)

    # Kill processes that have been hanging too long
    Enum.each(updated_tracker, fn {pid, start_time} ->
      if Process.alive?(pid) do
        time_elapsed = current_time - start_time

        if time_elapsed > kill_timeout and httpc_handle_answer_process?(pid) do
          Logger.error("Killing hanging httpc:handle_answer/3 process #{inspect(pid)} after #{time_elapsed}ms")
          Process.exit(pid, :kill)
        end
      end
    end)

    # Clean up dead processes from tracker
    updated_tracker
    |> Enum.filter(fn {pid, _} -> Process.alive?(pid) end)
    |> Map.new()
  end

  defp httpc_handle_answer_process?(pid) do
    case Process.info(pid, :current_function) do
      {:current_function, {:httpc, :handle_answer, 3}} -> true
      {:current_function, {:httpc_handler, :handle_answer, _}} -> true
      {:current_function, {:httpc_handler, :handle_info, _}} -> true
      _ -> false
    end
  end
end
