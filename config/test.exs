import Config

# Configure to use the mock client for all tests
config :unleash, :client, Unleash.ClientMock
