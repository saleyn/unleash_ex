import Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# third-party users, it should be done in your "mix.exs" file.

# You can configure your application as:
#
#     config :unleash_ex, key: :value
#
# and access this configuration in your application as:
#
#     Application.get_env(:unleash_ex, :key)
#
# You can also configure a third-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).


config :unleash,
  sticky_fields: %{
    "userId" => :user_id,
    "sessionId" => :session_id,
    "remoteAddress" => :remote_address,
    "appName" => :app_name,
    "environment" => :environment
  }

cfg_file = Path.expand("#{config_env()}.exs", __DIR__)

File.exists?(cfg_file) && import_config cfg_file
