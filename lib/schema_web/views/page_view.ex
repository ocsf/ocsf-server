defmodule SchemaWeb.PageView do
  alias SchemaWeb.SchemaController
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
    case class[:profiles] || [] do
      [] ->
        ""

      list ->
        [
          "<h5 class='mt-3'>Profiles</h5>",
          "Applicable profiles: ",
          Stream.filter(list, fn profile -> Map.has_key?(profiles, profile) end)
          |> Enum.map_join(", ", fn name ->
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

  @spec format_attribute_caption(any, String.t() | atom, nil | maybe_improper_list | map) :: any
  def format_attribute_caption(conn, entity_key, entity) do
    {observable_type_id, observable_kind} = observable_type_id_and_kind(entity)

    caption = entity[:caption] || to_string(entity_key)

    caption =
      case observable_type_id do
        nil ->
          caption

        type_id ->
          type_id = to_string(type_id)

          [
            caption,
            " <sup><a href=\"",
            SchemaWeb.Router.Helpers.static_path(conn, "/objects/observable"),
            "#type_id-",
            type_id,
            "\" data-toggle=\"tooltip\" title=\"Observable Type ID ",
            type_id,
            " (",
            observable_kind,
            ")\">O</a></sup>"
          ]
      end

    case entity[:extension] do
      nil -> caption
      extension -> [caption, " <sup>#{extension}</sup>"]
    end
  end

  def observable_type_id_and_kind(entity) do
    case entity[:meta_type] do
      :dictionary_type ->
        {entity[:observable], "Type"}

      :object ->
        {entity[:observable], "Object"}

      :dictionary_attribute ->
        direct = entity[:observable]

        if direct != nil do
          {direct, "Attribute"}
        else
          # Could be an observable by type or object
          by_type = observable_by_type(entity)

          if by_type != nil do
            {by_type, "Type"}
          else
            by_object = observable_by_object(entity)

            if by_object != nil do
              {by_object, "Object"}
            else
              {nil, nil}
            end
          end
        end

      # :class ->
      #   {nil, nil}

      meta_type ->
        Logger.warning("Unexpected meta type #{inspect(meta_type)} in #{inspect(entity)}")
        {nil, nil}
    end
  end

  def observable_by_type(entity) do
    Schema.dictionary()[:types][:attributes][Schema.Utils.to_uid(entity[:type])][:observable]
  end

  def observable_by_object(entity) do
    entity_type = entity[:type]
    entity_object_type = entity[:object_type]

    if entity_type == "object_t" && entity_object_type != nil do
      Schema.object(Schema.Utils.to_uid(entity_object_type))[:observable]
    else
      nil
    end
  end

  @spec format_attribute_name(String.t() | atom()) :: any
  def format_attribute_name(name) do
    Path.basename(to_string(name))
  end

  @spec format_class_attribute_source(String.t(), map()) :: String.t()
  def format_class_attribute_source(class_name, field) do
    all_classes = Schema.all_classes()
    source = field[:_source]
    {ok, path} = build_class_hierarchy(Schema.Utils.to_uid(class_name), source, all_classes)

    if ok do
      format_class_hierarchy(path, all_classes)
    else
      to_string(source)
    end
  end

  # Build a class hierarchy path from class to parent_class.
  # Returns {true, path} when a path is found, and {false, []} otherwise.
  @spec build_class_hierarchy(atom(), atom(), map(), list()) :: {boolean(), list()}
  defp build_class_hierarchy(
         class,
         parent_class,
         all_classes,
         path_result \\ []
       ) do
    cond do
      class == nil ->
        {false, []}

      class == parent_class ->
        {true, [class | path_result]}

      true ->
        build_class_hierarchy(
          Schema.Utils.to_uid(all_classes[class][:extends]),
          parent_class,
          all_classes,
          [class | path_result]
        )
    end
  end

  defp format_class_hierarchy(path, all_classes) do
    Enum.map(
      path,
      fn class ->
        class_info = all_classes[class]

        if class_info[:hidden?] do
          [all_classes[class][:caption], " (hidden class)"]
        else
          all_classes[class][:caption]
        end
      end
    )
    |> Enum.intersperse(" ← ")
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

    deprecation_status =
      if field[:"@deprecated"] != nil do
        base <> "deprecated "
      else
        base <> "not-deprecated "
      end

    classes =
      if required?(field) do
        deprecation_status <> "required "
      else
        if recommended?(field) do
          deprecation_status <> "recommended "
        else
          deprecation_status <> "optional "
        end
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
    r == "required"
  end

  defp recommended?(field) do
    r = Map.get(field, :requirement)
    r == "recommended"
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
        max_len <> "<br>" <> r
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

  @spec format_desc(String.t() | atom(), map()) :: any
  def format_desc(key, obj) do
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
              id = to_string(id)
              desc = Map.get(item, :description) || ""

              [
                "<tr class='bg-transparent'><td style='width: 25px' class='text-right' id='",
                to_string(key),
                "-",
                id,
                "'><code>",
                id,
                "</code></td><td class='textnowrap'>",
                Map.get(item, :caption, id),
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
      "</strong><br>" | acc
    ]
  end

  def constraints(:just_one, list, acc) do
    ["Only one attribute can be present: <strong>", Enum.join(list, ", "), "</strong><br>" | acc]
  end

  def constraints(name, list, acc) do
    [Atom.to_string(name), ": <strong>", Enum.join(list, ", "), "</strong><br>" | acc]
  end

  def associations(rules) do
    Enum.reduce(rules, [], fn {name, list}, acc ->
      associations(name, list, acc)
    end)
  end

  def associations(name, list, acc) do
    [Atom.to_string(name), ": ", Enum.join(list, ", "), "<br>" | acc]
  end

  defp reverse_sort_links(links) do
    Enum.sort(
      links,
      fn link1, link2 ->
        link1[:group] >= link2[:group] and link1[:caption] >= link2[:caption]
      end
    )
  end

  defp to_css_selector(value) do
    String.replace(to_string(value), "/", "-")
  end

  defp collapse_html(collapse_id, text, items) do
    [
      "<a class=\"dropdown-toggle\" data-toggle=\"collapse\" data-target=\"#",
      collapse_id,
      "\" aria-expanded=\"false\" aria-controls=\"",
      collapse_id,
      "\">",
      text,
      "</a><br>",
      "<div class=\"collapse multi-collapse\" id=\"",
      collapse_id,
      "\">",
      items,
      "</div>"
    ]
  end

  @spec dictionary_links(any(), String.t(), list(Schema.Cache.link_t())) :: <<>> | list()
  def dictionary_links(_, _, nil), do: ""
  def dictionary_links(_, _, []), do: ""

  def dictionary_links(conn, attribute_name, links) do
    groups = Enum.group_by(links, fn link -> link[:group] end)

    commons_html = dictionary_links_common_to_html(conn, groups[:common])

    classes_html =
      if Enum.empty?(commons_html) do
        dictionary_links_class_to_html(conn, attribute_name, groups[:class])
      else
        Enum.intersperse(
          [
            "Referenced by all classes",
            dictionary_links_class_updated_to_html(conn, attribute_name, groups[:class])
          ],
          "<br>"
        )
      end

    objects_html = links_object_to_html(conn, attribute_name, groups[:object], :collapse)

    Enum.reject([commons_html, classes_html, objects_html], &Enum.empty?/1)
    |> Enum.intersperse("<hr>")
  end

  defp dictionary_links_common_to_html(_, nil), do: []

  defp dictionary_links_common_to_html(conn, linked_classes) do
    reverse_sort_links(linked_classes)
    |> Enum.reduce(
      [],
      fn _link, acc ->
        [
          [
            "<a href=\"",
            SchemaWeb.Router.Helpers.static_path(conn, "/base_event"),
            "\" data-toggle=\"tooltip\ title=\"Directly referenced\">Base Event Class</a>"
          ]
          | acc
        ]
      end
    )
    |> Enum.intersperse("<br>")
  end

  defp dictionary_links_class_to_html(_, _, nil), do: []

  defp dictionary_links_class_to_html(conn, attribute_name, linked_classes) do
    classes = SchemaController.classes(conn.params())
    all_classes = Schema.all_classes()
    attribute_key = Schema.Utils.descope_to_uid(attribute_name)

    html_list =
      reverse_sort_links(linked_classes)
      |> Enum.reduce(
        [],
        fn link, acc ->
          type_path = SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link[:type])
          class_key = Schema.Utils.to_uid(link[:type])
          source = classes[class_key][:attributes][attribute_key][:_source]

          cond do
            source == nil ->
              # This means the attribute's :_source is incorrectly missing. Show with warning.
              [
                [
                  "<a href=\"",
                  type_path,
                  "\" data-toggle=\"tooltip\" title=\"No source\">",
                  link[:caption],
                  " Class</a> <span class=\"bg-warning\">No source</span>"
                ]
                | acc
              ]

            source == class_key ->
              [
                [
                  "<a href=\"",
                  type_path,
                  "\" data-toggle=\"tooltip\" title=\"Directly referenced\">",
                  link[:caption],
                  " Class</a>"
                ]
                | acc
              ]

            true ->
              # Any indirect situation, including through hidden classes
              {ok, path} = build_class_hierarchy(class_key, source, all_classes)

              if ok do
                [
                  [
                    "<a href=\"",
                    type_path,
                    "\" data-toggle=\"tooltip\" title=\"Indirectly referenced: ",
                    format_class_hierarchy(path, all_classes),
                    "\">",
                    link[:caption],
                    " Class</a>"
                  ]
                  | acc
                ]
              else
                # This means there's a bad class hierarchy. Show with warning.
                [
                  [
                    "<a href=\"",
                    type_path,
                    "\" data-toggle=\"tooltip\" title=\"Referenced via unknown parent\">",
                    link[:caption],
                    " Class</a> <span class=\"bg-warning\">Unknown parent</span>"
                  ]
                  | acc
                ]
              end
          end
        end
      )

    if Enum.empty?(html_list) do
      []
    else
      noun_text = if length(html_list) == 1, do: " class", else: " classes"

      collapse_html(
        ["class-links-", to_css_selector(attribute_name)],
        ["Referenced by ", Integer.to_string(length(html_list)), noun_text],
        Enum.intersperse(html_list, "<br>")
      )
    end
  end

  defp dictionary_links_class_updated_to_html(_, _, nil), do: []

  defp dictionary_links_class_updated_to_html(conn, attribute_name, linked_classes) do
    classes = SchemaController.classes(conn.params())
    all_classes = Schema.all_classes()
    attribute_key = Schema.Utils.descope_to_uid(attribute_name)

    html_list =
      reverse_sort_links(linked_classes)
      |> Enum.reduce(
        [],
        fn link, acc ->
          class_key = Schema.Utils.to_uid(link[:type])

          type_path = SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link[:type])
          source = classes[class_key][:attributes][attribute_key][:_source]

          cond do
            source == nil ->
              # This means the attribute's :_source is incorrectly missing. Show with warning.
              [
                [
                  "<a href=\"",
                  type_path,
                  "\" data-toggle=\"tooltip\" title=\"No source\">",
                  link[:caption],
                  " Class</a> <span class=\"bg-warning\">No source</span>"
                ]
                | acc
              ]

            source == :base_event ->
              # Skip base_event source:
              #   - Reduces noise
              #   - It is redundant with showing Base Event Class separately
              acc

            source == class_key ->
              [
                [
                  "<a href=\"",
                  type_path,
                  "\" data-toggle=\"tooltip\" title=\"Directly updated\">",
                  link[:caption],
                  " Class</a>"
                ]
                | acc
              ]

            true ->
              # Any indirect situation, including through hidden classes
              {ok, path} = build_class_hierarchy(class_key, source, all_classes)

              if ok do
                [
                  [
                    "<a href=\"",
                    type_path,
                    "\" data-toggle=\"tooltip\" title=\"Indirectly updated: ",
                    format_class_hierarchy(path, all_classes),
                    "\">",
                    link[:caption],
                    " Class</a>"
                  ]
                  | acc
                ]
              else
                # This means there's a bad class hierarchy. Show with warning.
                [
                  [
                    "<a href=\"",
                    type_path,
                    "\" data-toggle=\"tooltip\" title=\"Updated via unknown parent\">",
                    link[:caption],
                    " Class</a> <span class=\"bg-warning\">Unknown parent</span>"
                  ]
                  | acc
                ]
              end
          end
        end
      )

    if Enum.empty?(html_list) do
      []
    else
      noun_text = if length(html_list) == 1, do: " class", else: " classes"

      collapse_html(
        ["class-links-", to_css_selector(attribute_name)],
        [
          "Updated in ",
          Integer.to_string(length(html_list)),
          noun_text
        ],
        Enum.intersperse(html_list, "<br>")
      )
    end
  end

  # Used by dictionary_links and profile_links
  defp links_object_to_html(_, _, nil, _), do: []

  defp links_object_to_html(conn, name, linked_objects, list_presentation) do
    html_list =
      reverse_sort_links(linked_objects)
      |> Enum.reduce(
        [],
        fn link, acc ->
          [
            [
              "<a href=\"",
              SchemaWeb.Router.Helpers.static_path(conn, "/objects/" <> link[:type]),
              "\">",
              link[:caption],
              " Object</a>"
            ]
            | acc
          ]
        end
      )

    cond do
      Enum.empty?(html_list) ->
        []

      list_presentation == :collapse ->
        noun_text = if length(html_list) == 1, do: " object", else: " objects"

        collapse_html(
          ["object-links-", to_css_selector(name)],
          ["Referenced by ", Integer.to_string(length(html_list)), noun_text],
          Enum.intersperse(html_list, "<br>")
        )

      true ->
        Enum.intersperse(html_list, "<br>")
    end
  end

  @spec object_links(any(), String.t(), list(Schema.Cache.link_t()), nil | :collapse) ::
          <<>> | list()
  def object_links(conn, name, links, list_presentation \\ nil)
  def object_links(_, _, nil, _), do: ""
  def object_links(_, _, [], _), do: ""

  def object_links(conn, name, links, list_presentation) do
    groups = Enum.group_by(links, fn link -> link[:group] end)

    commons_html = object_links_common_to_html(conn, groups[:common], list_presentation)
    classes_html = object_links_class_to_html(conn, name, groups[:class], list_presentation)
    objects_html = object_links_object_to_html(conn, name, groups[:object], list_presentation)

    Enum.reject([commons_html, classes_html, objects_html], &Enum.empty?/1)
    |> Enum.intersperse("<hr>")
  end

  defp link_attributes(link) do
    attribute_keys = link[:attribute_keys]
    attribute_keys_size = if attribute_keys == nil, do: 0, else: MapSet.size(attribute_keys)

    case attribute_keys_size do
      0 ->
        "No attributes"

      1 ->
        ["Attribute: ", to_string(Enum.at(attribute_keys, 0))]

      _ ->
        ["Attributes: ", Enum.intersperse(Enum.map(attribute_keys, &to_string/1), ", ")]
    end
  end

  defp object_links_common_to_html(_, nil, _), do: []

  defp object_links_common_to_html(conn, linked_classes, list_presentation) do
    html_list =
      reverse_sort_links(linked_classes)
      |> Enum.reduce(
        [],
        fn link, acc ->
          type_path =
            if link[:type] == "base_event" do
              SchemaWeb.Router.Helpers.static_path(conn, "/base_event")
            else
              SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link[:type])
            end

          [
            if list_presentation == :collapse do
              [
                "<a href=\"",
                type_path,
                "\" data-toggle=\"tooltip\" title=\"",
                link_attributes(link),
                "\">",
                link[:caption],
                " Class</a>"
              ]
            else
              [
                "<dt><a href=\"",
                type_path,
                "\">",
                link[:caption],
                " Class</a><dd class=\"ml-3\">",
                link_attributes(link)
              ]
            end
            | acc
          ]
        end
      )

    cond do
      Enum.empty?(html_list) ->
        []

      list_presentation == :collapse ->
        Enum.intersperse(html_list, "<br>")

      true ->
        ["<dl class=\"m-0\">", html_list, "</dl>"]
    end
  end

  defp object_links_class_to_html(_, _, nil, _), do: []

  defp object_links_class_to_html(conn, name, linked_classes, list_presentation) do
    html_list =
      reverse_sort_links(linked_classes)
      |> Enum.reduce(
        [],
        fn link, acc ->
          type_path = SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link[:type])

          [
            if list_presentation == :collapse do
              [
                "<a href=\"",
                type_path,
                "\" data-toggle=\"tooltip\" title=\"",
                link_attributes(link),
                "\">",
                link[:caption],
                " Class</a>"
              ]
            else
              [
                "<dt><a href=\"",
                type_path,
                "\">",
                link[:caption],
                " Class</a><dd class=\"ml-3\">",
                link_attributes(link)
              ]
            end
            | acc
          ]
        end
      )

    cond do
      Enum.empty?(html_list) ->
        []

      list_presentation == :collapse ->
        noun_text = if length(html_list) == 1, do: " class", else: " classes"

        collapse_html(
          ["class-links-", to_css_selector(name)],
          ["Referenced by ", Integer.to_string(length(html_list)), noun_text],
          Enum.intersperse(html_list, "<br>")
        )

      true ->
        ["<dl class=\"m-0\">", html_list, "</dl>"]
    end
  end

  defp object_links_object_to_html(_, _, nil, _), do: []

  defp object_links_object_to_html(conn, name, linked_objects, list_presentation) do
    html_list =
      reverse_sort_links(linked_objects)
      |> Enum.reduce(
        [],
        fn link, acc ->
          type_path = SchemaWeb.Router.Helpers.static_path(conn, "/objects/" <> link[:type])

          [
            if list_presentation == :collapse do
              [
                "<a href=\"",
                type_path,
                "\" data-toggle=\"tooltip\" title=\"",
                link_attributes(link),
                "\">",
                link[:caption],
                " Object</a>"
              ]
            else
              [
                "<dt><a href=\"",
                type_path,
                "\">",
                link[:caption],
                " Object</a><dd class=\"ml-3\">",
                link_attributes(link)
              ]
            end
            | acc
          ]
        end
      )

    cond do
      Enum.empty?(html_list) ->
        []

      list_presentation == :collapse ->
        noun_text = if length(html_list) == 1, do: " object", else: " objects"

        collapse_html(
          ["object-links-", to_css_selector(name)],
          ["Referenced by ", Integer.to_string(length(html_list)), noun_text],
          Enum.intersperse(html_list, "<br>")
        )

      true ->
        ["<dl class=\"m-0\">", html_list, "</dl>"]
    end
  end

  @spec profile_links(any(), String.t(), list(Schema.Cache.link_t()), nil | :collapse) ::
          <<>> | list()
  def profile_links(conn, profile_name, links, list_presentation \\ nil)
  def profile_links(_, _, nil, _), do: ""
  def profile_links(_, _, [], _), do: ""

  def profile_links(conn, profile_name, links, list_presentation) do
    groups = Enum.group_by(links, fn link -> link[:group] end)

    commons_html = profile_links_common_to_html(conn, groups[:common])

    classes_html =
      profile_links_class_to_html(conn, profile_name, groups[:class], list_presentation)

    objects_html = links_object_to_html(conn, profile_name, groups[:object], list_presentation)

    Enum.reject([commons_html, classes_html, objects_html], &Enum.empty?/1)
    |> Enum.intersperse("<hr>")
  end

  defp profile_links_common_to_html(_, nil), do: []

  defp profile_links_common_to_html(conn, linked_classes) do
    reverse_sort_links(linked_classes)
    |> Enum.reduce(
      [],
      fn _link, acc ->
        [
          [
            "<a href=\"",
            SchemaWeb.Router.Helpers.static_path(conn, "/base_event"),
            "\">Base Event Class</a>"
          ]
          | acc
        ]
      end
    )
    |> Enum.intersperse("<br>")
  end

  defp profile_links_class_to_html(_, _, nil, _), do: []

  defp profile_links_class_to_html(conn, profile_name, linked_classes, list_presentation) do
    html_list =
      reverse_sort_links(linked_classes)
      |> Enum.reduce(
        [],
        fn link, acc ->
          [
            [
              "<a href=\"",
              SchemaWeb.Router.Helpers.static_path(conn, "/classes/" <> link[:type]),
              "\">",
              link[:caption],
              " Class</a>"
            ]
            | acc
          ]
        end
      )

    cond do
      Enum.empty?(html_list) ->
        []

      list_presentation == :collapse ->
        noun_text = if length(html_list) == 1, do: " class", else: " classes"

        collapse_html(
          ["class-links-", to_css_selector(profile_name)],
          ["Referenced by ", Integer.to_string(length(html_list)), noun_text],
          Enum.intersperse(html_list, "<br>")
        )

      true ->
        Enum.intersperse(html_list, "<br>")
    end
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
      "<div class='text-dark mt-2'><span class='bg-warning'>DEPRECATED since v",
      Map.get(deprecated, :since),
      "</span></div>",
      Map.get(deprecated, :message)
    ]
  end
end
