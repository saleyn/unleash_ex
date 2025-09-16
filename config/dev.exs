import Config

# SimpleHttp.get("https://unleash-edge.use1-rdev.k8s.adgear.com/api/client/features?namePrefix=rtb-gateway", ssl: [verify: :verify_none], headers_format: :binary, headers: %{"Authorization" => "*:development.9e17cec7f2c42734c458c566ec07883cac1edf2915faa7b66c63aa79", "Content-Type" => "application/json"}) |> elem(1) |> Map.get(:body) |> Jason.decode!

config :unleash,
  disable_client: false,
  disable_metrics: false,
  url: "http://localhost:4242/api/",
  app_env: :dev,
  appname: "unleash_test"
