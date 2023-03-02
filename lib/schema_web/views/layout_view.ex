defmodule SchemaWeb.LayoutView do
  use SchemaWeb, :view

  def format_profile(nil) do
    ""
  end

  def format_profile(profile) do
    Enum.reduce(profile[:attributes], [], fn {name, _}, acc ->
      [Atom.to_string(name) | acc]
    end)
    |> Enum.join("\n")
  end

  def format_extension(nil) do
    ""
  end

  def format_extension(extension) do
    extension[:version] || "undefined"
  end

  def select_versions(_conn) do
    current = Schema.version()

    case Schemas.versions() do
      [] ->
        [
          "<option value='",
          current,
          "' selected=true disabled=true>",
          "v#{current}",
          "</option>"
        ]

      versions ->
        Enum.map(versions, fn {version, _path} ->
          [
            "<option value='",
            "/#{version}",
            if version == current do
              "' selected=true disabled=true>"
            else
              "'>"
            end,
            "v#{version}",
            "</option>"
          ]
        end)
    end
  end
end
