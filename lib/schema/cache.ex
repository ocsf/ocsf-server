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
  alias Schema.Types

  require Logger

  @enforce_keys [:version, :dictionary, :categories, :base_event, :classes, :objects]
  defstruct ~w[version dictionary base_event categories classes objects]a

  @spec new(map()) :: __MODULE__.t()
  def new(version) do
    %__MODULE__{
      version: version,
      dictionary: Map.new(),
      categories: Map.new(),
      base_event: Map.new(),
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

    categories = JsonReader.read_categories() |> update_categories()
    dictionary = JsonReader.read_dictionary()

    {base_event, classes} = read_classes(categories[:attributes])
    objects = read_objects()

    # clean up the cached files
    JsonReader.cleanup()

    dictionary = Utils.update_dictionary(dictionary, base_event, classes, objects)
    objects = Utils.update_objects(dictionary, objects)

    new(version)
    |> set_categories(categories)
    |> set_dictionary(dictionary)
    |> set_base_event(base_event)
    |> set_classes(classes)
    |> set_objects(objects)
  end

  @doc """
    Returns the event extensions.
  """
  @spec extensions :: map()
  def extensions(), do: Schema.JsonReader.extensions()

  @spec reset :: :ok
  def reset(), do: Schema.JsonReader.reset()

  @spec reset(binary) :: :ok
  def reset(path), do: Schema.JsonReader.reset(path)

  @spec version(__MODULE__.t()) :: String.t()
  def version(%__MODULE__{version: version}), do: version[:version]

  @spec dictionary(__MODULE__.t()) :: dictionary_t()
  def dictionary(%__MODULE__{dictionary: dictionary}), do: dictionary

  @spec categories(__MODULE__.t()) :: map()
  def categories(%__MODULE__{categories: categories}), do: categories

  @spec category(__MODULE__.t(), any) :: nil | category_t()
  def category(%__MODULE__{categories: categories}, id) do
    Map.get(categories[:attributes], id)
  end

  @spec classes(__MODULE__.t()) :: list
  def classes(%__MODULE__{classes: classes}), do: classes

  @spec export_classes(__MODULE__.t()) :: map()
  def export_classes(%__MODULE__{classes: classes, dictionary: dictionary}) do
    Enum.map(classes, fn {name, class} ->
      {name, enrich(class, dictionary[:attributes])}
    end)
    |> Map.new()
  end

  @spec class(__MODULE__.t(), atom()) :: nil | class_t()
  def class(%__MODULE__{dictionary: dictionary, base_event: base_event}, :base_event) do
    enrich(base_event, dictionary[:attributes])
  end

  def class(%__MODULE__{dictionary: dictionary, classes: classes}, id) do
    case Map.get(classes, id) do
      nil ->
        nil

      class ->
        enrich(class, dictionary[:attributes])
    end
  end

  @spec find_class(Schema.Cache.t(), any) :: nil | map
  def find_class(%__MODULE__{dictionary: dictionary, classes: classes}, uid) do
    case Enum.find(classes, fn {_, class} -> class[:uid] == uid end) do
      {_, class} -> enrich(class, dictionary[:attributes])
      nil -> nil
    end
  end

  @spec objects(__MODULE__.t()) :: map()
  def objects(%__MODULE__{objects: objects}), do: objects

  @spec export_objects(__MODULE__.t()) :: map()
  def export_objects(%__MODULE__{dictionary: dictionary, objects: objects}) do
    Enum.map(objects, fn {name, object} ->
      {name, enrich(object, dictionary[:attributes])}
    end)
    |> Map.new()
  end

  @spec object(__MODULE__.t(), any) :: nil | object_t()
  def object(%__MODULE__{dictionary: dictionary, objects: objects}, id) do
    case Map.get(objects, id) do
      nil ->
        nil

      object ->
        enrich(object, dictionary[:attributes])
    end
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

  # Add category_uid, class_uid, and event_uid
  defp enrich_class({name, class}, categories) do
    data =
      class
      |> update_class_id(categories)
      |> add_event_id(name)
      |> add_class_id(name)
      |> add_category_id(name, categories)

    {name, data}
  end

  defp update_categories(categories) do
    Map.update!(categories, :attributes, fn attributes ->
      Enum.map(attributes, fn {name, cat} ->
        update_category_id(name, cat, cat[:extension_id])
      end)
      |> Map.new()
    end)
  end

  defp update_category_id(name, category, nil) do
    {name, category}
  end

  defp update_category_id(name, category, extension) do
    {name, Map.update!(category, :uid, fn uid -> Types.category_uid(extension, uid) end)}
  end

  defp update_class_id(class, categories) do
    {key, category} = Utils.find_entity(categories, class, class[:category])

    class = Map.put(class, :category, Atom.to_string(key))
    class = Map.put(class, :category_name, category[:name])

    case class[:extension_id] do
      nil ->
        Map.update(class, :uid, 0, fn uid ->
          Types.class_uid(category[:uid], uid)
        end)

      ext ->
        Map.update(class, :uid, 0, fn uid ->
          Types.class_uid(Types.category_uid_ex(ext, category[:uid]), uid)
        end)
    end
  end

  defp add_event_id(data, name) do
    Map.update!(
      data,
      :attributes,
      fn attributes ->
        uid = attributes[:event_uid] || %{}
        enum = make_event_id(data, name, attributes)

        Map.put(attributes, :event_uid, Map.put(uid, :enum, enum))
      end
    )
    |> put_in([:attributes, :event_uid, :_source], name)
  end

  defp make_event_id(data, name, attributes) do
    id = attributes[:disposition_id] || %{}
    class_id = Types.event_uid(data[:uid] || 0, 0)
    caption = data[:name] || "UNKNOWN"

    case id[:enum] do
      nil ->
        Logger.warn("class '#{name}' has no disposition_id values")
        %{}

      values ->
        for {key, val} = value <- values, into: %{} do
          case key do
            :"-1" ->
              value

            _ ->
              {
                make_enum_id(class_id, key),
                Map.put(val, :name, Types.event_name(caption, val[:name]))
              }
          end
        end
    end
    |> Map.put(
      integer_to_id(0, -1),
      Map.new(name: Types.event_name(caption, "Other"))
    )
    |> Map.put(
      integer_to_id(class_id, 0),
      Map.new(name: Types.event_name(caption, "Unknown"))
    )
  end

  defp make_enum_id(class_id, key) do
    integer_to_id(class_id, String.to_integer(Atom.to_string(key)))
  end

  defp integer_to_id(class_id, id) do
    Integer.to_string(class_id + id) |> String.to_atom()
  end

  defp add_class_id(data, name) do
    class_id =
      data[:uid]
      |> Integer.to_string()
      |> String.to_atom()

    enum = %{
      :name => data[:name],
      :description => data[:description]
    }

    data
    |> put_in([:attributes, :class_uid, :enum], %{class_id => enum})
    |> put_in([:attributes, :class_uid, :_source], name)
  end

  defp add_category_id(class, name, categories) do
    case class[:category] do
      nil ->
        Logger.warn("class '#{class[:type]}' has no category")

      cat_name ->
        {_key, category} = Utils.find_entity(categories, class, cat_name)

        if category == nil do
          Logger.warn("class '#{class[:type]}' has an invalid category: #{cat_name}")
          class
        else
          update_in(
            class,
            [:attributes, :category_uid, :enum],
            fn _enum ->
              id = Integer.to_string(category[:uid]) |> String.to_atom()
              %{id => category}
            end
          )
        end
        |> put_in([:attributes, :category_uid, :_source], name)
    end
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

  defp resolve_extends(classes) do
    Enum.map(classes, fn {name, class} -> {name, resolve_extends(classes, class)} end)
  end

  defp resolve_extends(classes, class) do
    case class[:extends] do
      nil ->
        class

      extends ->
        case super_class(classes, class, extends) do
          nil ->
            exit("Error: #{class[:name]} extends undefined class: #{extends}")

          base ->
            base = resolve_extends(classes, base)
            attributes = Utils.deep_merge(base[:attributes], class[:attributes])

            Map.merge(base, class)
            |> Map.delete(:extends)
            |> Map.put(:attributes, attributes)
        end
    end
  end

  defp super_class(classes, class, extends) do
    case class[:extension] do
      nil ->
        Map.get(classes, String.to_atom(extends))

      extension ->
        case Map.get(classes, Utils.to_uid(extension, extends)) do
          nil -> Map.get(classes, String.to_atom(extends))
          other -> other
        end
    end
  end

  defp update_see_also(classes) do
    Enum.map(classes, fn {name, class} -> update_see_also(name, class, classes) end)
  end

  defp update_see_also(name, class, classes) do
    see_also = find_see_also_classes(class, classes)

    if see_also != nil and length(see_also) > 0 do
      {name, Map.put(class, :see_also, see_also)}
    else
      {name, Map.delete(class, :see_also)}
    end
  end

  defp find_see_also_classes(class, classes) do
    see_also = class[:see_also]

    if see_also != nil do
      Enum.map(
        see_also,
        fn name ->
          case Utils.find_entity(classes, class, name) do
            {_, nil} ->
              Logger.warn("find_see_also_classes: #{name} not found")
              nil

            {_key, class} ->
              {Utils.make_path(class[:extension], name), class[:name]}
          end
        end
      )
      |> Enum.filter(fn elem -> elem != nil end)
    else
      nil
    end
  end

  defp set_dictionary(%__MODULE__{} = schema, dictionary) do
    struct(schema, dictionary: dictionary)
  end

  defp set_categories(%__MODULE__{} = schema, categories) do
    struct(schema, categories: categories)
  end

  defp set_base_event(%__MODULE__{} = schema, base_event) do
    struct(schema, base_event: base_event)
  end

  defp set_classes(%__MODULE__{} = schema, classes) do
    struct(schema, classes: classes)
  end

  defp set_objects(%__MODULE__{} = schema, objects) do
    struct(schema, objects: objects)
  end
end
