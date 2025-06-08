import Config

config :unleash,
  auth_token:
    System.get_env("UNLEASH_CLIENT_KEY") ||
      raise(RuntimeError, message: "Missing UNLEASH_AUTH_TOKEN!")
