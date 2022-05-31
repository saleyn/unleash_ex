:unleash
|> Application.load()
|> case do
  :ok -> :unleash
  {:error, {:already_loaded, :unleash}} -> :unleash
end
|> Application.spec(:applications)
|> Enum.each(fn app -> Application.ensure_all_started(app) end)

ExUnit.configure(exclude: [skip: true], formatters: [JUnitFormatter, ExUnit.CLIFormatter])
ExUnit.start()
