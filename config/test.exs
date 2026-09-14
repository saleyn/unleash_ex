import Config

# Configure to use the mock client for all tests
config :unleash, :client, Unleash.ClientMock

# Use standard GenServer metrics in tests for compatibility with existing test setup
config :unleash, :fast_metrics, false

# Disable telemetry (matches production default); telemetry-asserting tests
# re-enable it per-test via Application.put_env
config :unleash, :disable_telemetry, true
