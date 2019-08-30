# Unleash

[![pipeline status](https://gitlab.com/afontaine/unleash_ex/badges/master/pipeline.svg)](https://gitlab.com/afontaine/unleash_ex/commits/master)
[![coverage report](https://gitlab.com/afontaine/unleash_ex/badges/master/coverage.svg)](https://gitlab.com/afontaine/unleash_ex/commits/master)
[![Hex version badge](https://img.shields.io/hexpm/v/unleash.svg)](https://hex.pm/packages/unleash)
[![License badge](https://img.shields.io/hexpm/l/unleash.svg)](https://gitlab.com/afontaine/unleash_ex/blob/master/LICENSE)

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
    {:unleash_ex, "~> 1.0"}
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
  disable_metrics: false # Whether or not to send metrics,
  retries: -1 # How many times to retry on failure, -1 disables limit
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
