# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Utils do
  @moduledoc """
  Defines map helper functions.
  """
  require Logger

  @spec to_uid(binary() | atom()) :: atom
  def to_uid(name) when is_binary(name) do
    String.to_atom(name)
  end

  def to_uid(name) when is_atom(name) do
    name
  end

  @spec to_uid(binary() | nil, binary() | atom()) :: atom()
  def to_uid(nil, name) when is_atom(name) do
    name
  end

  def to_uid(extension, name) when is_atom(name) do
    to_uid(extension, Atom.to_string(name))
  end

  def to_uid(extension, name) do
    make_path(extension, name) |> to_uid()
  end

  @spec make_path(binary() | nil, binary()) :: binary()
  def make_path(nil, name), do: name
  def make_path(extension, name), do: Path.join(extension, name)

  def find_entity(map, entity, name) when is_binary(name) do
    find_entity(map, entity, String.to_atom(name))
  end

  def find_entity(map, entity, key) do
    case entity[:extension] do
      nil ->
        {key, map[key]}

      extension ->
        ext_key = to_uid(extension, key)

        case Map.get(map, ext_key) do
          nil ->
            {key, map[key]}

          other ->
            {ext_key, other}
        end
    end
  end

  @spec update_dictionary(map, map, map, map) :: map
  def update_dictionary(dictionary, common, classes, objects) do
    dictionary
    |> add_common_links(common)
    |> link_classes(classes)
    |> link_objects(objects)
    |> update_data_types(objects)
    |> define_datetime_attributes()
  end

  @spec update_objects(map(), map()) :: map()
  def update_objects(objects, dictionary) do
    Enum.into(objects, %{}, fn {name, object} ->
      links = object_links(dictionary, Atom.to_string(name))
      {name, Map.put(object, :_links, links)}
    end)
  end

  defp object_links(dictionary, name) do
    Enum.filter(dictionary, fn {_name, map} -> Map.get(map, :object_type) == name end)
    |> Enum.map(fn {_, map} -> Map.get(map, :_links) end)
    |> List.flatten()
    |> Stream.filter(fn links -> links != nil end)
    |> Stream.uniq()
    |> Enum.to_list()
  end

  defp link_classes(dictionary, classes) do
    Enum.reduce(classes, dictionary, fn class, acc ->
      add_class_links(acc, class)
    end)
  end

  defp link_objects(dictionary, objects) do
    Enum.reduce(objects, dictionary, fn obj, acc ->
      add_object_links(acc, obj)
    end)
  end

  defp update_data_types(dictionary, objects) do
    Map.update!(dictionary, :attributes, fn attributes ->
      update_data_types(attributes, get_in(dictionary, [:types, :attributes]), objects)
    end)
  end

  defp update_data_types(attributes, types, objects) do
    Enum.into(attributes, %{}, fn {name, value} ->
      data =
        if value[:type] == "object_t" do
          update_object_type(name, value, objects)
        else
          update_data_type(name, value, types)
        end

      {name, data}
    end)
  end

  defp update_object_type(name, value, objects) do
    key = value[:object_type]

    case find_entity(objects, value, key) do
      {key, nil} ->
        Logger.warn("undefined object type: #{key}, for #{name}")
        Map.put(value, :object_name, "_undefined_")

      {key, object} ->
        value
        |> Map.put(:object_name, object[:caption])
        |> Map.put(:object_type, Atom.to_string(key))
    end
  end

  defp update_data_type(name, value, types) do
    type =
      case value[:type] do
        nil ->
          Logger.warn("missing data type for: #{name}, will use string_t type")
          "string_t"

        t ->
          t
      end

    case types[String.to_atom(type)] do
      nil ->
        Logger.warn("undefined data type: #{name}: #{type}")
        value

      type ->
        Map.put(value, :type_name, type[:caption])
    end
  end

  # Adds attribute's used-by links to the dictionary.
  defp add_common_links(dict, class) do
    Map.update!(dict, :attributes, fn attributes ->
      link = {:common, class[:name], class[:caption]}

      update_attributes(
        class,
        attributes,
        link,
        &update_dictionary_links/2
      )
    end)
  end

  defp add_class_links(dict, {name, class}) do
    Map.update!(dict, :attributes, fn attributes ->
      type =
        case class[:name] do
          nil -> "base_event"
          _ -> Atom.to_string(name)
        end

      link = {:class, type, class[:caption] || "*No name*"}

      update_attributes(
        class,
        attributes,
        link,
        &update_dictionary_links/2
      )
    end)
  end

  defp update_dictionary_links(item, link) do
    Map.update(item, :_links, [link], fn links ->
      [{_, id, _} | _] = links
      if id > 0, do: [link | links], else: links
    end)
  end

  defp add_object_links(dict, {name, obj}) do
    Map.update!(dict, :attributes, fn dictionary ->
      link = {:object, Atom.to_string(name), obj[:caption] || "*No name*"}
      update_attributes(obj, dictionary, link, &update_object_links/2)
    end)
  end

  defp update_object_links(item, link) do
    Map.update(item, :_links, [link], fn links ->
      [link | links]
    end)
  end

  defp update_attributes(item, dictionary, link, update_links) do
    name = item[:caption]
    attributes = item[:attributes]

    Enum.reduce(attributes, dictionary, fn {k, v}, acc ->
      case find_entity(acc, item, k) do
        {_, nil} ->
          case String.split(Atom.to_string(v[:_source]), "/") do
            [ext, _] ->
              ext_key = String.to_atom("#{ext}/#{k}")

              data =
                case Map.get(acc, ext_key) do
                  nil ->
                    update_links.(v, link)

                  attr ->
                    deep_merge(attr, v) |> update_links.(link)
                end

              Map.put(acc, ext_key, data)

            _ ->
              Logger.warn("'#{name}' uses undefined attribute: #{k}: #{inspect(v)}")
              acc
          end

        {key, item} ->
          Map.put(acc, key, update_links.(item, link))
      end
    end)
  end

  @spec deep_merge(map, map) :: map
  def deep_merge(left, right) do
    Map.merge(left, right, &deep_resolve/3)
  end

  # Key exists in both and both values are maps as well, then they can be merged recursively
  defp deep_resolve(_key, left, right) when is_map(left) and is_map(right) do
    if map_size(left) == 0 do
      right
    else
      if map_size(right) == 0 do
        left
      else
        deep_merge(left, right)
      end
    end
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the right.
  defp deep_resolve(_key, _left, right) do
    right
  end

  @doc """
    Filter attributes based on the given profiles.
  """
  @spec apply_profiles(Enum.t(), nil | list() | MapSet.t()) :: Enum.t()
  def apply_profiles(attributes, nil) do
    attributes
  end

  def apply_profiles(attributes, profiles) when is_list(profiles) do
    profiles = MapSet.new(profiles)
    apply_profiles(attributes, profiles, MapSet.size(profiles))
  end

  def apply_profiles(attributes, %MapSet{} = profiles) do
    apply_profiles(attributes, profiles, MapSet.size(profiles))
  end

  def apply_profiles(attributes, _profiles) do
    attributes
  end

  def apply_profiles(attributes, _profiles, 0) do
    remove_profiles(attributes)
  end

  def apply_profiles(attributes, profiles, _size) do
    Enum.filter(attributes, fn {_k, v} ->
      case v[:profile] do
        nil -> true
        profile -> MapSet.member?(profiles, profile)
      end
    end)
  end

  def remove_profiles(attributes) do
    Enum.filter(attributes, fn {_k, v} -> Map.has_key?(v, :profile) == false end)
  end

  defp define_datetime_attributes(dictionary) do
    Map.update!(dictionary, :attributes, fn attributes ->
      Enum.reduce(attributes, %{}, fn {name, attribute}, acc ->
        define_datetime_attribute(acc, attribute[:type], name, attribute)
      end)
    end)
  end

  defp define_datetime_attribute(acc, "timestamp_t", name, attribute) do
    acc
    |> Map.put(name, attribute)
    |> Map.put(make_datetime(name), datetime_attribute(attribute))
  end

  defp define_datetime_attribute(acc, _type, name, attribute) do
    Map.put(acc, name, attribute)
  end

  defp datetime_attribute(attribute) do
    attribute
    |> Map.put(:type, "datetime_t")
    |> Map.put(:type_name, "Datetime")
  end

  def make_datetime(name) do
    (Atom.to_string(name) <> "_dt") |> String.to_atom()
  end
end
