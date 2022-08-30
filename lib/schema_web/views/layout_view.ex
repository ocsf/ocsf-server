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

end
