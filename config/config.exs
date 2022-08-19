import Config

port = System.get_env("HTTP_PORT") || System.get_env("PORT") || 8000
port_ssl = System.get_env("HTTPS_PORT") || 8443

certfile = System.get_env("HTTPS_CERT_FILE") || "priv/cert/selfsigned.pem"
keyfile  = System.get_env("HTTPS_KEY_FILE") || "priv/cert/selfsigned_key.pem"

path = System.get_env("SCHEMA_PATH") || "/"

# Configures the endpoint
config :schema_server, SchemaWeb.Endpoint,
  http: [port: port],
  https: [
    port: port_ssl,
    cipher_suite: :strong,
    certfile: certfile,
    keyfile: keyfile
  ],
#  url: [host: "localhost", path: path],
  secret_key_base: "HUvG8AlzaUpVx5PShWbGv6JpifzM/d46Rj3mxAIddA7DJ9qKg6df8sG6PsKXScAh",
  render_errors: [view: SchemaWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: Schema.PubSub

# Configures Elixir's Logger
config :logger, :console,
  handle_otp_reports: true,
  handle_sasl_reports: true,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Add Markdown Template Engine for Phoenix
config :phoenix, :template_engines, md: PhoenixMarkdown.Engine
config :phoenix_markdown, :server_tags, :all

config :phoenix_markdown, :earmark, %{
  gfm: true,
  breaks: true,
  compact_output: false,
  smartypants: false
}

config :schema_server, :phoenix_swagger,
  swagger_files: %{
    "priv/static/swagger.json" => [
      router: SchemaWeb.Router, 
      endpoint: SchemaWeb.Endpoint
    ]
  }

config :phoenix_swagger, json_library: Jason

# Configures the location of the schema files
config :schema_server, Schema.JsonReader, home: System.get_env("SCHEMA_DIR")
config :schema_server, Schema.Application, extension: System.get_env("SCHEMA_EXTENSION")

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
