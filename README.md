# Unleash

`Unleash` is a client for the
[Unleash Toggle Service](https://unleash.github.io/).

The primary use is `Unleash.enabled?/2` or `Unleash.enabled?/3` to check whether
or not the given feature flag is enabled.

```elixir
iex> Unleash.enabled?(:my_feature)
false

iex> Unleash.enabled?(:my_feature, true)
true

iex> Unleash.enabled?(:my_feature, context)
true

iex> Unleash.enabled?(:my_feature, context, false)
true
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `unleash_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:unleash, "~> 1.0"}
  ]
end
```

## Configuration

There are many configuration options available, and they are listed below with
their defaults. These go into the relevant `config/*.exs` file.

```elixir
config :unleash, Unleash,
  url: "", # The URL of the Unleash server to connect to, should include up to http://base.url/api
  appname: "", # The app name, used for registration
  instance_id: "", # The instance ID, used for metrics tracking
  metrics_period: 10 * 60 * 1000, # Send metrics every 10 minutes, in milliseconds
  features_period: 15 * 1000, # Poll for new flags every 15 seconds, in milliseconds
  strategies: Unleash.Strategies, # Which module to request for toggle strategies
  backup_file: nil, # Backup file in the event that contacting the server fails
  custom_http_headers: [], # A keyword list of custom headers to send to the server
  disable_client: false, # Whether or not to enable the client
  disable_metrics: false, # Whether or not to send metrics,
  retries: -1 # How many times to retry on failure, -1 disables limit
  app_env: :dev # Which environment we're in
```

`:custom_http_headers` should follow the format prescribed by
`t:Mojito.headers/0`

`:strategies` should be a module that implements
`c:Unleash.Strategies.strategies/0`. See [Extensibility](#extensibility)
for more information.

## Extensibility

If you need to create your own strategies, you can extend the `Unleash` client
by implementing the callbacks in both `Unleash.Strategy` and
`Unleash.Strategies` as well as passing your new `Strategies` module in as
configuration:

1. Create your new strategy. See `Unleash.Strategy` for details on the correct
    API and `Unleash.Strategy.Utils` for helpful utilities.

    ```elixir
    defmodule MyApp.Strategy.Environment do
      use Unleash.Strategy

      def enabled?(%{"environments" => environments}, _context) do
        with {:ok, environment} <- MyApp.Config.get_environment(),
             environment = List.to_string(environment) do
          {Utils.in_list?(environments, environment, &String.downcase/1),
           %{environment: environment, environments: environments}}
        end
      end
    end
    ```

1. Create a new strategies module. See `Unleash.Strategies` for details on the correct
    API.

    ```elixir
    defmodule MyApp.Strategies do
      @behaviour Unleash.Strategies

      def strategies do
        [{"environment", MyApp.Strategy.Environment}] ++ Unleash.Strategies.strateges()
      end
    end
    ```

1. Configure your application to use your new strategies list.

    ```elixir
    config :unleash, Unleash, strategies: MyApp.Strategies
    ```

## Telemetry events

The following events are emitted by the Unleash:

* `[:unleash, :feature, :enabled?, :start]` - dispatched by `Unleash` whenever
a feature state has been requested.
  * Measurement:  `%{system_time: system_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), feature: String.t()}`
* `[:unleash, :feature, :enabled?, :stop]` - dispatched by `Unleash` whenever
a feature check has successfully returned a result.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), feature: String.t(), result: boolean(), reason: atom(), strategy_evaluations: [{String.t(), boolean()}], feature_enabled: boolean()}`
* `[:unleash, :feature, :enabled?, :exception]` - dispatched by `Unleash` after
exceptions on fetching a feature's activation state.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), feature: String.t(), kind: :throw | :error | :exit, reason: term(), stacktrace: Exception.stacktrace()}`
* `[:unleash, :client, :features, :start]` - dispatched by `Unleash.Client` whenever
it start to fetch features from a remote Unleash server.
  * Measurement:  `%{system_time: system_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), etag: String.t() | nil, url: String.t()}`
* `[:unleash, :client, :features, :stop]` - dispatched by `Unleash.Client` whenever
it finishes to fetch features from a remote Unleash server.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), etag: String.t() | nil, url: String.t(), http_response_status: pos_integer | nil, error: struct() | nil}`
* `[:unleash, :client, :features, :exception]` - dispatched by `Unleash.Client` after
exceptions on fetching features.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), etag: String.t() | nil, url: String.t(), kind: :throw | :error | :exit, reason: term(), stacktrace: Exception.stacktrace()}`
* `[:unleash, :client, :register, :start]` - dispatched by `Unleash.Client` whenever
it starts to register in an Unleash server.
  * Measurement:  `%{system_time: system_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), url: String.t(), sdk_version: String.t(), strategies: [String.t()], interval: pos_integer}`
* `[:unleash, :client, :register, :stop]` - dispatched by `Unleash.Client` whenever
it finishes to register in an Unleash server.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), url: String.t(), sdk_version: String.t(), strategies: [String.t()], interval: pos_integer, http_response_status: pos_integer | nil, error: struct() | nil}`
* `[:unleash, :client, :register, :exception]` - dispatched by `Unleash.Client` after
exceptions on registering in an Unleash server.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), url: String.t(), sdk_version: String.t(), strategies: [String.t()], interval: pos_integer, kind: :throw | :error | :exit, reason: term(), stacktrace: Exception.stacktrace()}`
* `[:unleash, :client, :push_metrics, :start]` - dispatched by `Unleash.Client` whenever
it starts to push metrics to an Unleash server.
  * Measurement:  `%{system_time: system_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), url: String.t()}`
* `[:unleash, :client, :push_metrics, :stop]` - dispatched by `Unleash.Client` whenever
it finishes to push metrics to an Unleash server.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), url: String.t(), http_response_status: pos_integer | nil, error: struct() | nil}`
* `[:unleash, :client, :push_metrics, :exception]` - dispatched by `Unleash.Client` after
exceptions on pushing metrics to an Unleash server.
  * Measurement:  `%{duration: native_time, monotonic_time: monotonic_time}`
  * Metadata: `%{appname: String.t(), instance_id: String.t(), url: String.t(), kind: :throw | :error | :exit, reason: term(), stacktrace: Exception.stacktrace()}`
* `[:unleash, :repo, :schedule]` - dispatched by `Unleash.Repo` when scheduling a poll to the server for metrics
  * Metadata: `%{appname: String.t(), instance_id: String.t(), retries: integer(), etag: String.t(), interval: pos_integer()}`
* `[:unleash, :repo, :backup_file_update]` - dispatched by `Unleash.Repo` when it writes features to the backup file.
  * Metadata: `%{appname: String.t(), instance_id: String.t(), content: String.t(), filename: String.t()}`
* `[:unleash, :repo, :disable_polling]` - dispatched by `Unleash.Repo` when polling gets 
disabled due to retries running out or zero retries being specified initially.
  * Metadata: `%{appname: String.t(), instance_id: String.t(), retries: integer(), etag: String.t()}`
* `[:unleash, :repo, :features_update]` - dispatched by `Unleash.Repo` when features are updated.
  * Metadata: `%{appname: String.t(), instance_id: String.t(), retries: integer(), etag: String.t(), source: :remote | :cache | :backup_file}`