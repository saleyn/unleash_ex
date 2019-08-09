:unleash
|> Application.load()
|> case do
  :ok -> :unleash
end
|> Application.spec(:applications)
|> Enum.each(fn app -> Application.ensure_all_started(app) end)

ExUnit.configure(formatters: [JUnitFormatter, ExUnit.CLIFormatter])
ExUnit.start()
