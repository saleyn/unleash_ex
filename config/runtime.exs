import Config

config :unleash,
  url: System.get_env("UNLEASH_URL") || raise(RuntimeError, message: "Missing UNLEASH_URL!"),
  auth_token:
    System.get_env("UNLEASH_AUTH_TOKEN") ||
      raise(RuntimeError, message: "Missing UNLEASH_AUTH_TOKEN!")
