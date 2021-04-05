defmodule Schema.MixProject do
  use Mix.Project

  def project do
    build = System.get_env("GITHUB_RUN_NUMBER") || "SNAPSHOT"

    [
      releases: [
        schema_server: [
          steps: [:assemble, &write_version/1],
          include_executables_for: [:unix]
        ]
      ],
      app: :schema_server,
      version: "1.2.0-#{build}",
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Schema.Application, []},
      extra_applications: [:logger, :crypto, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.5"},
      {:phoenix_pubsub, "~> 2.0"},
      {:phoenix_html, "~> 2.14"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:gettext, "~> 0.11"},
      {:jason, "~> 1.2"},
      {:plug_cowboy, "~> 2.3"},
      {:number, "~> 1.0"},
      {:elixir_uuid, "~> 1.6", hex: :uuid_utils},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false}
    ]
  end

  # Write the version number
  defp write_version(rel) do
    case System.argv() do
      ["release" | _] ->
        # Write the version number
        version = Mix.Project.config()[:version]
        File.write(".version", version)

      _ ->
        :ok
    end

    rel
  end
end
