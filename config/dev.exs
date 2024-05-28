import Config

# SimpleHttp.get("https://unleash-edge.use1-rdev.k8s.adgear.com/api/client/features?namePrefix=rtb-gateway", ssl: [verify: :verify_none], headers_format: :binary, headers: %{"Authorization" => "*:development.9e17cec7f2c42734c458c566ec07883cac1edf2915faa7b66c63aa79", "Content-Type" => "application/json"}) |> elem(1) |> Map.get(:body) |> Jason.decode!

config :unleash,
  disable_client: true,
  http_client: Unleash.Http.SimpleHttp,
  http_opts: %{
    ssl: [verify: :verify_none],
    #ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get()],
    headers_format: :binary,
    headers: [
      "Content-Type": "application/json"
    ],
    debug: true
  },
  metrics_period: 15 * 1000,
  app_env: :dev
