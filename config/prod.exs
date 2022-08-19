import Config

# Do not print debug messages in production
config :logger,
  format: "$time $metadata[$level] $message\n",
  level: :info

config :phoenix, :serve_endpoints, true
