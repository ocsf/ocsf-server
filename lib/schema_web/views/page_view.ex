defmodule SchemaWeb.PageView do
  use SchemaWeb, :view

  require Logger

  def format_range([min, max]) do
    format_number(min) <> "-" <> format_number(max)
  end

  @spec format_requirement(nil | map) :: binary
  def format_requirement(field) do
    Map.get(field, :requirement) || "optional"
  end

  def field_classes(field) do
    base =
      if field[:_source] == :base_event do
        "base-event "
      else
        "event "
      end

    if required?(field) do
      base <> "required"
    else
      if reserved?(field) do
        base <> "reserved"
      else
        base <> "optional"
      end
    end
  end

  defp required?(field) do
    r = Map.get(field, :requirement)
    r == "required" or r == "recommended"
  end

  defp reserved?(field) do
    Map.get(field, :requirement) == "reserved"
  end

  def format_constraints(:string_t, field) do
    format_string_constrains(field)
  end

  def format_constraints(:integer_t, field) do
    format_integer_constrains(field)
  end

  def format_constraints(:long_t, field) do
    format_integer_constrains(field)
  end

  def format_constraints("string_t", field) do
    format_string_constrains(field)
  end

  def format_constraints("integer_t", field) do
    format_integer_constrains(field)
  end

  def format_constraints("long_t", field) do
    format_integer_constrains(field)
  end

  def format_constraints(:boolean_t, field) do
    case Map.get(field, :values) do
      nil -> ""
      values -> format_values(values)
    end
  end

  def format_constraints(nil, field) do
    format_max_len(field)
  end

  # format data type constraints: values, range, regex, and max_len
  def format_constraints(_type, field) do
    format_constraints(Map.get(field, :type), field)
  end

  defp format_integer_constrains(field) do
    case Map.get(field, :range) do
      nil ->
        format_values(Map.get(field, :values))

      r ->
        format_range(r)
    end
  end

  defp format_string_constrains(field) do
    max_len = format_max_len(field)

    case Map.get(field, :regex) do
      nil ->
        case max_len do
          "" ->
            format_values(Map.get(field, :values))

          len ->
            len
        end

      r ->
        max_len <> "</br>" <> r
    end
  end

  defp format_values(nil) do
    ""
  end

  defp format_values(values) do
    Enum.join(values, ", ")
  end

  defp format_max_len(field) do
    case Map.get(field, :max_len) do
      nil -> ""
      max -> "Max length: " <> format_number(max)
    end
  end

  def format_type(conn, field) when is_map(field) do
    type_str =
      case Map.get(field, :type) do
        "object_t" ->
          obj = Map.get(field, :object_type)
          obj_path = SchemaWeb.Router.Helpers.static_path(conn, "/objects/#{obj}")

          case Map.get(field, :object_name) do
            nil ->
              "<a href='#{obj_path}'>#{format_type(conn, obj)}</a>"

            obj_name ->
              format_object_path(obj_name, obj_path)
          end

        _type ->
          Map.get(field, :type_name) || ""
      end

    array? = Map.get(field, :is_array)

    if array? do
      type_str <> " Array"
    else
      type_str
    end
  end

  defp format_object_path(name, path) do
    if String.starts_with?(name, "*") do
      "<div class='text-danger'>#{name}</div>"
    else
      "<a href='#{path}'>#{name}</a>"
    end
  end

  @spec format_desc(nil | map) :: any
  def format_desc(obj) do
    description = Map.get(obj, :description)

    case Map.get(obj, :enum) do
      nil ->
        description

      values ->
        sorted =
          if Map.get(obj, :type) == "integer_t" do
            Enum.sort(
              values,
              fn {k1, _}, {k2, _} ->
                String.to_integer(Atom.to_string(k1)) >= String.to_integer(Atom.to_string(k2))
              end
            )
          else
            Enum.sort(values, fn {k1, _}, {k2, _} -> k1 >= k2 end)
          end

        [
          description,
          """
          <table class="mt-1 table-borderless"><tbody>
          """,
          Enum.reduce(
            sorted,
            [],
            fn {id, item}, acc ->
              desc = Map.get(item, :description) || ""

              [
                "<tr class='bg-transparent'><td style='width: 50px' class='text-right'><code>",
                Atom.to_string(id),
                "</code></td><td class='text-nowrap'>",
                Map.get(item, :name),
                "</td><td>",
                desc,
                "</td><tr>" | acc
              ]
            end
          ),
          "</tbody></table>"
        ]
    end
  end

  def links(_, _, nil), do: ""

  def links(conn, name, links) do
    groups =
      Enum.group_by(links, fn
        {type, _link, _name} ->
          type

        nil ->
          Logger.warn("group-by: found unused attribute of '#{name}' object")
          nil
      end)

    join_html(
      to_html(:commons, conn, groups[:common]),
      to_html(:classes, conn, groups[:class]),
      to_html(:objects, conn, groups[:object])
    )
  end

  defp join_html(commons, [], []), do: commons
  defp join_html([], classes, []), do: classes
  defp join_html(commons, _classes, []), do: commons
  defp join_html(_, [], objects), do: objects
  defp join_html([], classes, objects), do: [classes, "<hr/>", objects]
  defp join_html(commons, _classes, objects), do: [commons, "<hr/>", objects]

  defp to_html(_, _, nil), do: []

  defp to_html(:commons, conn, classes) do
    Enum.sort(classes, fn {type1, _, name1}, {type2, _, name2} ->
      type1 >= type2 and name1 >= name2
    end)
    |> Enum.reduce([], fn _, acc ->
      type_path = SchemaWeb.Router.Helpers.static_path(conn, "/base_event")
      ["<a href='", type_path, "'>", " Base Event</a>", ", " | acc]
    end)
    |> List.delete_at(-1)
  end

  defp to_html(:classes, conn, classes) do
    Enum.sort(classes, fn {type1, _, name1}, {type2, _, name2} ->
      type1 >= type2 and name1 >= name2
    end)
    |> Enum.reduce([], fn {_type, link, name}, acc ->
      type_path = SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link)
      ["<a href='", type_path, "'>", name, " Event</a>", ", " | acc]
    end)
    |> List.delete_at(-1)
  end

  defp to_html(:objects, conn, objects) do
    Enum.sort(objects, fn {type1, _, name1}, {type2, _, name2} ->
      type1 >= type2 and name1 >= name2
    end)
    |> Enum.reduce([], fn {_type, link, name}, acc ->
      type_path = SchemaWeb.Router.Helpers.static_path(conn, "/objects/" <> link)
      ["<a href='", type_path, "'>", name, " Object</a>", ", " | acc]
    end)
    |> List.delete_at(-1)
  end

  defp format_number(n) do
    Number.Delimit.number_to_delimited(n, precision: 0)
  end
end
