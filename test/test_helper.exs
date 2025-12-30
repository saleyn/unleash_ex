:unleash
|> Application.load()
|> case do
  :ok -> :unleash
  {:error, {:already_loaded, :unleash}} -> :unleash
end
|> Application.spec(:applications)
|> Enum.each(fn app -> Application.ensure_all_started(app) end)

# Set up global stubs that work across all processes
Mox.stub_with(Unleash.ClientMock, Unleash.ClientStub)

ExUnit.configure(exclude: [skip: true], formatters: [JUnitFormatter, ExUnit.CLIFormatter])
ExUnit.start()
