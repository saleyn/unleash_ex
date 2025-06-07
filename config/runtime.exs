import Config

config :unleash,
  auth_token:
    System.get_env("UNLEASH_AUTH_TOKEN") ||
      raise(RuntimeError, message: "Missing UNLEASH_AUTH_TOKEN!")
