import Config

config :unleash, Unleash,
  url: "https://unleash-edge.use1-rdev.k8s.adgear.com/api",
  appname: "dev",
  instance_id: "dev",
  auth_token: "default:development.9ff17cf481782c7c649faa996c726ffc3e03d1b3abc213d008feddf3",
  metrics_period: 15 * 1000,
  app_env: :dev
