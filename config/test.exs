import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :schema_server, SchemaWeb.Endpoint,
  http: [port: System.get_env("PORT") || 8000],
  server: false

# Only log warnings and errors in test mode
config :logger,
  level: :warning
