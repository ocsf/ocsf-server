defmodule Schema.Utils do
  @moduledoc """
  Defines map helper functions.
  """
  require Logger

  @links :_links

  @doc false
  def update_dictionary(dictionary, common, classes, objects) do
    dictionary
    |> add_common_links(common)
    |> link_classes(classes)
    |> link_objects(objects)
    |> update_data_types(objects)
  end

  def update_objects(dictionary, objects) do
    attributes = dictionary.attributes

    Enum.map(objects, fn {name, object} ->
      links = object_links(attributes, Atom.to_string(name))
      {name, Map.put(object, :_links, links)}
    end)
    |> Map.new()
  end

  defp object_links(dictionary, name) do
    Enum.filter(dictionary, fn {_name, map} -> Map.get(map, :object_type) == name end)
    |> Enum.map(fn {_, map} -> Map.get(map, :_links) end)
    |> List.flatten()
    |> Enum.uniq()
  end

  defp link_classes(dictionary, classes) do
    Enum.reduce(classes, dictionary, fn {_, type}, acc ->
      add_class_links(acc, type)
    end)
  end

  defp link_objects(dictionary, objects) do
    Enum.reduce(objects, dictionary, fn obj, acc ->
      add_object_links(acc, obj)
    end)
  end

  defp update_data_types(dictionary, objects) do
    Map.update!(dictionary, :attributes, fn attributes ->
      update_data_types(attributes, dictionary.types[:attributes], objects)
    end)
  end

  defp update_data_types(attributes, types, objects) do
    Enum.map(attributes, fn {name, value} ->
      data =
        if value.type == "object_t" do
          update_object_type(name, value, objects)
        else
          update_data_type(name, value, types)
        end

      {name, data}
    end)
    |> Map.new()
  end

  defp update_object_type(name, value, objects) do
    t = String.to_atom(value.object_type)

    case objects[t] do
      nil ->
        Logger.warn("Undefined object type: #{t}, for #{name}")
        value

      object ->
        Map.put(value, :object_name, object.name)
    end
  end

  defp update_data_type(name, value, types) do
    type = value.type

    case types[String.to_atom(type)] do
      nil ->
        Logger.warn("Undefined type: #{name}: #{type}")
        value

      type ->
        Map.put(value, :type_name, type.name)
    end
  end

  # Adds attribute-used-by links to the dictionary.
  defp add_common_links(dict, type) do
    Map.update!(dict, :attributes, fn attributes ->
      link = {:common, type[:type], type[:name]}

      update_attributes(
        type[:name],
        type[:attributes],
        attributes,
        link,
        &update_dictionary_links/2
      )
    end)
  end

  defp add_class_links(dict, type) do
    Map.update!(dict, :attributes, fn attributes ->
      link = {:class, type[:type] || "event", type[:name] || "*No name*"}

      update_attributes(
        type[:name],
        type[:attributes],
        attributes,
        link,
        &update_dictionary_links/2
      )
    end)
  end

  defp update_dictionary_links(item, link) do
    Map.update(item, @links, [link], fn links ->
      [{_, id, _} | _] = links
      if id > 0, do: [link | links], else: links
    end)
  end

  defp add_object_links(dict, {link, obj}) do
    Map.update!(dict, :attributes, fn attributes ->
      link = {:object, Atom.to_string(link), obj[:name] || "*No name*"}
      update_attributes(obj[:name], obj[:attributes], attributes, link, &update_object_links/2)
    end)
  end

  defp update_attributes(name, target, attributes, link, update_links) do
    Enum.reduce(target, attributes, fn {k, _v}, acc ->
      case acc[k] do
        nil ->
          Logger.error("dictionary: missing attribute: #{k} for #{name}")
          acc

        item ->
          Map.put(acc, k, update_links.(item, link))
      end
    end)
  end

  defp update_object_links(item, link) do
    Map.update(item, @links, [link], fn links ->
      [link | links]
    end)
  end

  @spec deep_merge(map, map) :: map
  def deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both maps, and both values are maps as well.
  # These can be merged recursively.
  defp deep_resolve(key, %{} = left, %{} = right) do
    if map_size(left) == 0 do
      right
    else
      if map_size(right) == 0 do
        left
      else
        if key == :enum do
          # merge enums
          put_required(left, right)
          |> Enum.map(fn {k, v} ->
            item = Map.get(left, k)

            if map_size(v) > 0 do
              if item == nil do
                {k, v}
              else
                {k, Map.merge(item, v)}
              end
            else
              {k, item}
            end
          end)
          |> Enum.into(%{})
        else
          deep_merge(left, right)
        end
      end
    end
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  defp put_required(left, right) do
    right
    |> add_required(:"0", left)
    |> add_required(:"-1", left)
  end

  defp add_required(right, key, left) do
    put_not_nil(right, key, Map.get(left, key))
  end

  defp put_not_nil(map, _k, nil), do: map

  defp put_not_nil(map, k, v) do
    Map.put(map, k, v)
  end
end
