integration_enabled? =
  System.get_env("EX_DBOS_RUN_INTEGRATION") in ["1", "true", "TRUE", "yes", "YES"]

excludes = if integration_enabled?, do: [], else: [integration: true]

ExUnit.start(exclude: excludes)
