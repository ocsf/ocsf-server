defmodule SchemaWeb.PageView do
  use SchemaWeb, :view

  require Logger

  def class_graph_path(conn, data) do
    class_name = data[:name]

    case data[:extension] do
      nil ->
        Routes.static_path(conn, "/class/graph/" <> class_name)

      extension ->
        Routes.static_path(conn, "/class/graph/" <> extension <> "/" <> class_name)
    end
  end

  def class_path(conn, data) do
    class_name = data[:name]

    case data[:extension] do
      nil ->
        Routes.static_path(conn, "/classes/" <> class_name)

      extension ->
        Routes.static_path(conn, "/classes/" <> extension <> "/" <> class_name)
    end
  end

  def object_graph_path(conn, data) do
    object_name = data[:name]

    case data[:extension] do
      nil ->
        Routes.static_path(conn, "/object/graph/" <> object_name)

      extension ->
        Routes.static_path(conn, "/object/graph/" <> extension <> "/" <> object_name)
    end
  end

  def object_path(conn, data) do
    object_name = data[:name]

    case data[:extension] do
      nil ->
        Routes.static_path(conn, "/objects/" <> object_name)

      extension ->
        Routes.static_path(conn, "/objects/" <> extension <> "/" <> object_name)
    end
  end

  def class_profiles(conn, class, profiles) do
    case (class[:profiles] || []) do
      [] ->
        ""
      list ->
        [
          "<h5>Profiles</h5>",
          "Applicable profiles: ",
          Enum.map_join(list, ", ", fn name ->
            profile_link(conn, get_in(profiles, [name, :caption]), name)
          end),
          "."
        ]
    end
  end

  defp profile_link(_conn, nil, name) do
    name
  end
  
  defp profile_link(conn, caption, name) do
    path = Routes.static_path(conn, "/profiles/" <> name)
    "<a href='#{path}'>#{caption}</a>"
  end
  
  def class_examples(class) do
    format_class_examples(class[:examples])
  end

  defp format_class_examples(nil) do
    ""
  end

  defp format_class_examples([]) do
    ""
  end

  defp format_class_examples(examples) do
    [
      "<strong>Examples: </strong>",
      Enum.map_join(examples, ", ", fn {_uid, name, path} ->
        "<a target='_blank' href='#{path}'>#{name}</a>"
      end)
    ]
  end

  def format_profiles(nil) do
    ""
  end

  def format_profiles(profiles) do
    ["data-profiles='", Enum.join(profiles, ","), "'"]
  end

  @spec format_caption(any, nil | maybe_improper_list | map) :: any
  def format_caption(name, field) do
    name = field[:caption] || name

    name =
      case field[:uid] do
        nil -> name
        uid -> name <> "<span class='uid'> [#{uid}]</span>"
      end

    case field[:extension] do
      nil -> name
      extension -> name <> " <sup>#{extension}</sup>"
    end
  end

  @spec format_attribute_caption(any, nil | maybe_improper_list | map) :: any
  def format_attribute_caption(name, field) do
    name = field[:caption] || name

    name =
      case field[:observable] do
        nil -> name
        _ -> name <> " <sup>O</sup>"
      end

    case field[:extension] do
      nil -> name
      extension -> name <> " <sup>#{extension}</sup>"
    end
  end

  @spec format_attribute_name(binary()) :: any
  def format_attribute_name(name) do
    Path.basename(name)
  end

  @spec format_range([nil | number | Decimal.t(), ...]) :: nonempty_binary
  def format_range([min, max]) do
    format_number(min) <> "-" <> format_number(max)
  end

  @spec format_requirement(nil | map) :: binary
  def format_requirement(field) do
    Map.get(field, :requirement) || "optional"
  end

  @spec field_classes(map) :: nonempty_binary
  def field_classes(field) do
    base =
      if field[:_source] == :base_event or field[:_source] == :event do
        "base-event "
      else
        "event "
      end

    classes =
      if required?(field) do
        base <> "required "
      else
        base <> "optional "
      end

    group = field[:group]

    classes =
      if group != nil do
        classes <> group
      else
        classes <> "no-group"
      end

    profile = field[:profile]

    if profile != nil do
      classes <> " " <> String.replace(profile, "/", "-")
    else
      classes <> " no-profile"
    end
  end

  defp required?(field) do
    r = Map.get(field, :requirement)
    r == "required" or r == "recommended"
  end

  def format_constraints(:string_t, field) do
    format_string_constraints(field)
  end

  def format_constraints(:integer_t, field) do
    format_integer_constraints(field)
  end

  def format_constraints(:long_t, field) do
    format_integer_constraints(field)
  end

  def format_constraints("string_t", field) do
    format_string_constraints(field)
  end

  def format_constraints("integer_t", field) do
    format_integer_constraints(field)
  end

  def format_constraints("long_t", field) do
    format_integer_constraints(field)
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

  defp format_integer_constraints(field) do
    case Map.get(field, :range) do
      nil ->
        format_values(Map.get(field, :values))

      r ->
        format_range(r)
    end
  end

  defp format_string_constraints(field) do
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

  @spec format_desc(map) :: any
  def format_desc(obj) do
    description = description(obj)

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
                "<tr class='bg-transparent'><td style='width: 25px' class='text-right'><code>",
                Atom.to_string(id),
                "</code></td><td class='textnowrap'>",
                Map.get(item, :caption, Atom.to_string(id)),
                "<div class='text-secondary'>",
                desc,
                "</div></td><tr>" | acc
              ]
            end
          ),
          "</tbody></table>"
        ]
    end
  end

  def constraints(rules) do
    Enum.reduce(rules, [], fn {name, list}, acc ->
      constraints(name, list, acc)
    end)
  end

  def constraints(_name, nil, acc) do
    acc
  end

  def constraints(_name, [], acc) do
    acc
  end

  def constraints(:at_least_one, list, acc) do
    [
      "At least one attribute must be present: <strong>",
      Enum.join(list, ", "),
      "</strong><br/>" | acc
    ]
  end

  def constraints(:just_one, list, acc) do
    ["Only one attribute can be present: <strong>", Enum.join(list, ", "), "</strong><br/>" | acc]
  end

  def constraints(name, list, acc) do
    [Atom.to_string(name), ": <strong>", Enum.join(list, ", "), "</strong><br/>" | acc]
  end

  def associations(rules) do
    Enum.reduce(rules, [], fn {name, list}, acc ->
      associations(name, list, acc)
    end)
  end

  def associations(name, list, acc) do
    [Atom.to_string(name), ": ", Enum.join(list, ", "), "<br/>" | acc]
  end

  def links(_, _, nil), do: ""
  def links(_, _, []), do: ""

  def links(conn, name, links) do
    groups =
      Enum.group_by(
        links,
        fn
          {type, _link, _name} ->
            type

          nil ->
            Logger.warning("group-by: found unused attribute of '#{name}' object")
            nil
        end
      )

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
    Enum.sort(
      classes,
      fn {type1, _, name1}, {type2, _, name2} ->
        type1 >= type2 and name1 >= name2
      end
    )
    |> Enum.reduce(
      [],
      fn _, acc ->
        type_path = SchemaWeb.Router.Helpers.static_path(conn, "/base_event")
        ["<a href='", type_path, "'>", " Base Event</a>", ", " | acc]
      end
    )
    |> List.delete_at(-1)
  end

  defp to_html(:classes, conn, classes) do
    Enum.sort(
      classes,
      fn {type1, _, name1}, {type2, _, name2} ->
        type1 >= type2 and name1 >= name2
      end
    )
    |> Enum.reduce(
      [],
      fn {_type, link, name}, acc ->
        type_path = SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link)
        ["<a href='", type_path, "'>", name, " Event</a>", ", " | acc]
      end
    )
    |> List.delete_at(-1)
  end

  defp to_html(:objects, conn, objects) do
    Enum.sort(
      objects,
      fn {type1, _, name1}, {type2, _, name2} ->
        type1 >= type2 and name1 >= name2
      end
    )
    |> Enum.reduce(
      [],
      fn {_type, link, name}, acc ->
        type_path = SchemaWeb.Router.Helpers.static_path(conn, "/objects/" <> link)
        ["<a href='", type_path, "'>", name, " Object</a>", ", " | acc]
      end
    )
    |> List.delete_at(-1)
  end

  defp format_number(n) do
    Number.Delimit.number_to_delimited(n, precision: 0)
  end

  def description(map) do
    deprecated(map, Map.get(map, :"@deprecated"))
  end
  
  defp deprecated(map, nil) do
    Map.get(map, :description)
  end
  
  defp deprecated(map, deprecated) do
    [
      Map.get(map, :description),
      "<div class='text-dark mt-2'><span class='bg-warning'>DEPRECATED</span> ",
      Map.get(deprecated, :message),
      "</div>"
    ]
  end

end
