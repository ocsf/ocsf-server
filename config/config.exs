import Config

port = System.get_env("HTTP_PORT") || System.get_env("PORT") || 8080
path = System.get_env("SCHEMA_PATH") || "/"

# Configures the endpoint
config :schema_server, SchemaWeb.Endpoint,
  http: [port: port],
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
config :schema_server, Schema.Application, home: System.get_env("SCHEMA_DIR") || "../ocsf-schema"
config :schema_server, Schema.Application, extension: System.get_env("SCHEMA_EXTENSION")
config :schema_server, Schema.Application, schema_home: System.get_env("SCHEMA_HOME")

# Configure the schema example's repo path and local dicrectory
config :schema_server, Schema.Examples,
  repo: System.get_env("EXAMPLES_REPO") || "https://github.com/ocsf/examples/tree/main"

config :schema_server, Schema.Examples,
  home: System.get_env("EXAMPLES_PATH") || "../examples"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
