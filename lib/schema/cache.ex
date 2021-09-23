# Copyright 2021 Splunk Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Cache do
  @moduledoc """
  Builds the schema cache.
  """

  alias Schema.Utils
  alias Schema.JsonReader

  require Logger

  @enforce_keys [:version, :dictionary, :categories, :common, :classes, :objects]
  defstruct ~w[version dictionary common categories classes objects]a

  @spec new(map()) :: __MODULE__.t()
  def new(version) do
    %__MODULE__{
      version: version,
      dictionary: Map.new(),
      categories: Map.new(),
      common: Map.new(),
      classes: Map.new(),
      objects: Map.new()
    }
  end

  @type t() :: %__MODULE__{}
  @type class_t() :: map()
  @type object_t() :: map()
  @type category_t() :: map()
  @type dictionary_t() :: map()

  @doc """
  Load the schema files and initialize the cache.
  """
  @spec init() :: __MODULE__.t()
  def init() do
    version = JsonReader.read_version()

    categories = JsonReader.read_categories()
    dictionary = JsonReader.read_dictionary()

    {common, classes} = read_classes(categories.attributes)
    objects = read_objects()

    # clean up the cached files
    JsonReader.cleanup()

    dictionary = Utils.update_dictionary(dictionary, common, classes, objects)
    objects = Utils.update_objects(dictionary, objects)

    new(version)
    |> set_categories(categories)
    |> set_dictionary(dictionary)
    |> set_common(common)
    |> set_classes(classes)
    |> set_objects(objects)
  end

  @spec version(__MODULE__.t()) :: String.t()
  def version(%__MODULE__{version: version}), do: version[:version]

  @spec dictionary(__MODULE__.t()) :: dictionary_t()
  def dictionary(%__MODULE__{dictionary: dictionary}), do: dictionary

  @spec categories(__MODULE__.t()) :: map()
  def categories(%__MODULE__{categories: categories}), do: categories

  @spec categories(__MODULE__.t(), any) :: nil | category_t()
  def categories(%__MODULE__{categories: categories, classes: classes}, id) do
    case Map.get(categories.attributes, id) do
      nil ->
        nil

      category ->
        add_classes({id, category}, classes)
    end
  end

  @spec classes(__MODULE__.t()) :: list
  def classes(%__MODULE__{classes: classes}), do: classes

  @spec classes(__MODULE__.t(), atom()) :: nil | class_t()
  def classes(%__MODULE__{dictionary: dictionary, common: common}, :base_event) do
    enrich(common, dictionary.attributes)
  end

  def classes(%__MODULE__{dictionary: dictionary, classes: classes}, id) do
    case Map.get(classes, id) do
      nil ->
        nil

      class ->
        enrich(class, dictionary.attributes)
    end
  end

  def find_class(%__MODULE__{dictionary: dictionary, classes: classes}, uid) do
    case Enum.find(classes, fn {_, class} -> class[:uid] == uid end) do
      {_, class} -> enrich(class, dictionary.attributes)
      nil -> nil
    end
  end

  @spec objects(__MODULE__.t()) :: map()
  def objects(%__MODULE__{objects: objects}), do: objects

  @spec objects(__MODULE__.t(), any) :: nil | object_t()
  def objects(%__MODULE__{dictionary: dictionary, objects: objects}, id) do
    case Map.get(objects, id) do
      nil ->
        nil

      object ->
        enrich(object, dictionary.attributes)
    end
  end

  defp add_classes({id, category}, classes) do
    category_id = Atom.to_string(id)

    list =
      Enum.filter(
        classes,
        fn {_name, class} ->
          Map.get(class, :category) == category_id
        end
      )

    Map.put(category, :classes, list)
  end

  defp enrich(map, dictionary) do
    Map.update!(map, :attributes, fn list -> update_attributes(list, dictionary) end)
  end

  defp update_attributes(list, dictionary) do
    Enum.map(list, fn {name, attribute} ->
      case dictionary[name] do
        nil ->
          Logger.warn("undefined attribute: #{name}")
          {name, attribute}

        base ->
          {name, Utils.deep_merge(base, attribute)}
      end
    end)
  end

  @spec read_classes(map) :: {map, map}
  def read_classes(categories) do
    {base, classes} = read_classes()

    classes =
      classes
      |> Stream.map(fn {name, map} -> {name, resolve_extends(classes, map)} end)
      # remove intermediate classes
      |> Stream.filter(fn {_name, class} -> Map.has_key?(class, :uid) end)
      |> Stream.map(fn class -> enrich_class(class, categories) end)
      |> Enum.to_list()
      |> Map.new()

    {base, classes}
  end

  defp read_classes() do
    classes =
      JsonReader.read_classes()
      |> update_see_also()
      |> Enum.map(fn class -> attribute_source(class) end)
      |> Map.new()

    {Map.get(classes, :base_event), classes}
  end

  defp read_objects() do
    JsonReader.read_objects()
    |> resolve_extends()
    |> Enum.filter(fn {key, _object} ->
      # removes abstract objects
      !String.starts_with?(Atom.to_string(key), "_")
    end)
    |> Map.new()
  end

  # Add category_id, class_id, and event_id
  defp enrich_class({name, class}, categories) do
    data =
      class
      |> add_event_uid(name)
      |> add_class_id(name)
      |> add_category_id(name, categories)

    {name, data}
  end

  defp add_event_uid(data, name) do
    Map.update!(
      data,
      :attributes,
      fn attributes ->
        id = attributes[:disposition_id] || %{}
        uid = attributes[:event_id] || %{}
        class_id = (data[:uid] || 0) * 1000
        caption = data[:name] || "UNKNOWN"

        enum =
          case id[:enum] do
            nil ->
              %{"0" => "UNKNOWN"}

            values ->
              for {key, val} <- values, into: %{} do
                {
                  make_event_id(class_id, key),
                  Map.put(val, :name, make_event_name(caption, val[:name]))
                }
              end
          end
          |> Map.put(make_uid(0, -1), Map.new(name: make_event_name(caption, "Other")))
          |> Map.put(make_uid(class_id, 0), Map.new(name: make_event_name(caption, "Unknown")))

        Map.put(attributes, :event_id, Map.put(uid, :enum, enum))
      end
    )
    |> put_in([:attributes, :event_id, :_source], name)
  end

  defp make_event_name(caption, name) do
    caption <> ": " <> name
  end

  defp make_event_id(class_id, key) do
    make_uid(class_id, String.to_integer(Atom.to_string(key)))
  end

  defp make_uid(class_id, id) do
    Integer.to_string(class_id + id)
    |> String.to_atom()
  end

  defp add_class_id(data, name) do
    class_id =
      data.uid
      |> Integer.to_string()
      |> String.to_atom()

    enum = %{
      :name => data.name,
      :description => data[:description]
    }

    data
    |> put_in([:attributes, :class_id, :enum], %{class_id => enum})
    |> put_in([:attributes, :class_id, :_source], name)
  end

  defp add_category_id(data, name, categories) do
    category_name =
      data.category
      |> String.to_atom()

    category = categories[category_name]

    if category == nil do
      exit("#{data.name} has invalid category: #{category_name}")
    end

    update_in(
      data,
      [:attributes, :category_id, :enum],
      fn _enum ->
        id =
          Integer.to_string(category.id)
          |> String.to_atom()

        %{id => Map.delete(category, :class_id_range)}
      end
    )
    |> put_in([:attributes, :category_id, :_source], name)
  end

  defp attribute_source({name, map}) do
    data =
      Map.update(
        map,
        :attributes,
        [],
        fn attributes ->
          Enum.map(
            attributes,
            fn {key, attribute} ->
              {key, Map.put(attribute, :_source, name)}
            end
          )
          |> Map.new()
        end
      )

    {name, data}
  end

  defp resolve_extends(data) do
    Enum.map(data, fn {name, map} -> {name, resolve_extends(data, map)} end)
  end

  defp resolve_extends(data, map) do
    case map[:extends] do
      nil ->
        map

      key ->
        case Map.get(data, String.to_atom(key)) do
          nil ->
            exit("Error: #{map.name} extends undefined class: #{key}")

          base ->
            base = resolve_extends(data, base)
            attributes = Utils.deep_merge(base.attributes, map.attributes)

            Map.merge(base, map)
            |> Map.delete(:extends)
            |> Map.put(:attributes, attributes)
        end
    end
  end

  defp update_see_also(classes) do
    Enum.map(classes, fn {name, map} -> update_see_also(name, map, classes) end)
  end

  defp update_see_also(name, map, classes) do
    see_also = update_see_also(map[:see_also], classes)

    if see_also != nil and length(see_also) > 0 do
      {name, Map.put(map, :see_also, see_also)}
    else
      {name, map}
    end
  end

  defp update_see_also(see_also, classes) when is_list(see_also) do
    Enum.map(
      see_also,
      fn name ->
        case Map.get(classes, String.to_atom(name)) do
          nil ->
            nil

          class ->
            {name, class.name}
        end
      end
    )
    |> Enum.filter(fn elem -> elem != nil end)
  end

  defp update_see_also(_see_also, _classes) do
    nil
  end

  defp set_dictionary(%__MODULE__{} = schema, dictionary) do
    struct(schema, dictionary: dictionary)
  end

  defp set_categories(%__MODULE__{} = schema, categories) do
    struct(schema, categories: categories)
  end

  defp set_common(%__MODULE__{} = schema, common) do
    struct(schema, common: common)
  end

  defp set_classes(%__MODULE__{} = schema, classes) do
    struct(schema, classes: classes)
  end

  defp set_objects(%__MODULE__{} = schema, objects) do
    struct(schema, objects: objects)
  end
end
