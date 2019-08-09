import Config

config :unleash, Unleash,
  url: "http://localhost:4242",
  appname: "dev",
  instance_id: "dev",
  metrics_period: 15 * 1000
