import Config

# Do not print debug messages in production
config :logger,
  level: :info,
  metadata: [:mfa]

config :phoenix, :serve_endpoints, true
