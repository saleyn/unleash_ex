import Config

config :unleash, Unleash,
  url: "http://localhost:4242/api",
  appname: "dev",
  instance_id: "dev",
  metrics_period: 15 * 1000,
  app_env: :dev
