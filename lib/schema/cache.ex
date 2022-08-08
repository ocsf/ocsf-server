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

  @enforce_keys [:version, :profiles, :dictionary, :categories, :base_event, :classes, :objects]
  defstruct ~w[version profiles dictionary base_event categories classes objects]a

  @spec new(map()) :: __MODULE__.t()
  def new(version) do
    %__MODULE__{
      version: version,
      profiles: Map.new(),
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

    case version[:version] do
      "0.9.0" ->
        exit("Error: invalid version 0.9.0, please use version 0.10.0 or newer")

      _ ->
        :ok
    end

    categories = JsonReader.read_categories() |> update_categories()
    dictionary = JsonReader.read_dictionary() |> update_dictionary()

    {base_event, classes} = read_classes(categories[:attributes])
    objects = read_objects()

    profiles = JsonReader.read_profiles()

    # clean up the cached files
    JsonReader.cleanup()

    dictionary = Utils.update_dictionary(dictionary, base_event, classes, objects)
    attributes = dictionary[:attributes]

    objects =
      objects
      |> Utils.update_objects(attributes)
      |> update_observables(dictionary)
      |> update_object_profiles()

    classes = update_class_profiles(objects, classes)

    sanity_check(objects, attributes)
    sanity_check(classes, attributes)

    new(version)
    |> set_profiles(profiles)
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

  @spec profiles(__MODULE__.t()) :: map()
  def profiles(%__MODULE__{profiles: profiles}), do: profiles

  @spec data_types(__MODULE__.t()) :: map()
  def data_types(%__MODULE__{dictionary: dictionary}), do: dictionary[:types]

  @spec dictionary(__MODULE__.t()) :: dictionary_t()
  def dictionary(%__MODULE__{dictionary: dictionary}), do: dictionary

  @spec categories(__MODULE__.t()) :: map()
  def categories(%__MODULE__{categories: categories}), do: categories

  @spec category(__MODULE__.t(), any) :: nil | category_t()
  def category(%__MODULE__{categories: categories}, id) do
    Map.get(categories[:attributes], id)
  end

  @spec classes(__MODULE__.t()) :: map()
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
      case find_attribute(dictionary, name, attribute[:_source]) do
        nil ->
          Logger.warn("undefined attribute: #{name}: #{inspect(attribute)}")
          {name, attribute}

        base ->
          {name, Utils.deep_merge(base, attribute)}
      end
    end)
  end

  defp find_attribute(dictionary, name, source) do
    case Atom.to_string(source) |> String.split("/") do
      [_] ->
        dictionary[name]

      [ext, _] ->
        ext_name = String.to_atom("#{ext}/#{name}")
        dictionary[ext_name] || dictionary[name]
    end
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
      |> Enum.into(%{}, fn class -> attribute_source(class) end)

    {Map.get(classes, :base_event), classes}
  end

  defp read_objects() do
    JsonReader.read_objects()
    |> resolve_extends()
    |> Enum.filter(fn {key, _object} ->
      # removes abstract objects
      !String.starts_with?(Atom.to_string(key), "_")
    end)
    |> Enum.into(%{}, fn class -> attribute_source(class) end)
  end

  # Add category_uid, class_uid, and type_uid
  defp enrich_class({name, class}, categories) do
    data =
      class
      |> update_class_uid(categories)
      |> add_type_uid(name)
      |> add_class_uid(name)
      |> add_category_uid(name, categories)

    {name, data}
  end

  defp update_categories(categories) do
    Map.update!(categories, :attributes, fn attributes ->
      Enum.map(attributes, fn {name, cat} ->
        update_category_uid(name, cat, cat[:extension_id])
      end)
      |> Map.new()
    end)
  end

  defp update_category_uid(name, category, nil) do
    {name, category}
  end

  defp update_category_uid(name, category, extension) do
    {name, Map.update!(category, :uid, fn uid -> Types.category_uid(extension, uid) end)}
  end

  defp update_class_uid(class, categories) do
    {key, category} = Utils.find_entity(categories, class, class[:category])

    class = Map.put(class, :category, Atom.to_string(key))
    class = Map.put(class, :category_name, category[:caption])

    try do
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
    rescue
      ArithmeticError ->
        error("invalid class #{class[:name]}: #{inspect(Map.delete(class, :attributes))}")
    end
  end

  defp add_type_uid(data, name) do
    Map.update!(
      data,
      :attributes,
      fn attributes ->
        uid = attributes[:type_uid] || %{}
        enum = make_type_uid(data, name, attributes)

        Map.put(attributes, :type_uid, Map.put(uid, :enum, enum))
      end
    )
    |> put_in([:attributes, :type_uid, :_source], name)
  end

  defp make_type_uid(data, name, attributes) do
    class_uid = get_class_uid(data)
    caption = data[:caption] || "UNKNOWN"

    case event_id(attributes)[:enum] do
      nil ->
        Logger.warn("class '#{name}' has no activity_id nor disposition_id")
        %{}

      values ->
        enum_values(class_uid, caption, values)
    end
    |> Map.put(
      integer_to_id(0, -1),
      Map.new(caption: Types.type_name(caption, "Other"))
    )
    |> Map.put(
      integer_to_id(class_uid, 0),
      Map.new(caption: Types.type_name(caption, "Unknown"))
    )
  end

  defp event_id(attributes) do
    attributes[:activity_id] || attributes[:disposition_id] || %{}
  end

  defp get_class_uid(class) do
    Types.type_uid(class[:uid] || 0, 0)
  end

  defp enum_values(class_uid, caption, values) do
    for {key, val} = value <- values, into: %{} do
      case key do
        :"-1" ->
          value

        _ ->
          {
            make_enum_id(class_uid, key),
            Map.put(val, :caption, Types.type_name(caption, val[:caption]))
          }
      end
    end
  end

  defp make_enum_id(class_uid, key) do
    integer_to_id(class_uid, String.to_integer(Atom.to_string(key)))
  end

  defp integer_to_id(class_uid, id) do
    Integer.to_string(class_uid + id) |> String.to_atom()
  end

  defp add_class_uid(data, name) do
    class_uid =
      data[:uid]
      |> Integer.to_string()
      |> String.to_atom()

    enum = %{
      :caption => data[:caption],
      :description => data[:description]
    }

    data
    |> put_in([:attributes, :class_uid, :enum], %{class_uid => enum})
    |> put_in([:attributes, :class_uid, :_source], name)
  end

  defp add_category_uid(class, name, categories) do
    case class[:category] do
      nil ->
        Logger.warn("class '#{class[:name]}' has no category")

      cat_name ->
        {_key, category} = Utils.find_entity(categories, class, cat_name)

        if category == nil do
          Logger.warn("class '#{class[:name]}' has an invalid category: #{cat_name}")
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
          Enum.into(
            attributes,
            %{},
            fn {key, attribute} ->
              {key, Map.put(attribute, :_source, name)}
            end
          )
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
              {Utils.make_path(class[:extension], name), class[:caption]}
          end
        end
      )
      |> Enum.filter(fn elem -> elem != nil end)
    else
      nil
    end
  end

  defp set_profiles(%__MODULE__{} = schema, profiles) do
    struct(schema, profiles: profiles)
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

  defp update_observables(objects, dictionary) do
    if Map.has_key?(objects, :observable) do
      observable_types = get_in(dictionary, [:types, :attributes]) |> observables()
      observable_objects = observables(objects)

      Map.update!(objects, :observable, fn observable ->
        observable
        |> update_observable_types(observable_types)
        |> update_observable_types(observable_objects)
      end)
    else
      objects
    end
  end

  defp update_observable_types(observable, types) do
    update_in(observable, [:attributes, :type_id, :enum], fn enum ->
      Map.merge(enum, generate_observable_types(types))
    end)
  end

  defp generate_observable_types(types) do
    Enum.into(types, %{}, fn {_name, type} ->
      k = Integer.to_string(type[:observable]) |> String.to_atom()
      v = %{caption: type[:caption], description: type[:description]}
      {k, v}
    end)
  end

  defp observables(e) do
    Enum.filter(e, fn {_, value} ->
      Map.has_key?(value, :observable) and Map.get(value, :observable) > 0
    end)
  end

  defp sanity_check(map, dictionary) do
    Enum.each(map, fn {name, value} ->
      Enum.each(value[:attributes], fn {key, attribute} ->
        if is_nil(attribute[:description]) do
          desc = get_in(dictionary, [key, :description]) || ""

          if String.contains?(desc, "See specific usage") do
            Logger.warn("Please update the description for #{name}.#{key}: #{desc}")
          end
        end
      end)
    end)
  end

  defp update_object_profiles(objects) do
    Enum.reduce(objects, objects, fn {name, object}, acc ->
      if Map.has_key?(object, :profiles) do
        update_object_profiles(name, object, acc)
      else
        acc
      end
    end)
  end

  defp update_object_profiles(_name, object, objects) do
    case object[:_links] do
      nil ->
        objects

      links ->
        Enum.reduce(links, objects, fn {type, key, _}, acc ->
          case type do
            :object ->
              Map.update!(acc, String.to_atom(key), fn obj ->
                Map.put(obj, :profiles, merge_profiles(obj[:profiles], object[:profiles]))
              end)

            _ ->
              acc
          end
        end)
    end
  end

  defp update_class_profiles(objects, classes) do
    Enum.reduce(objects, classes, fn {name, object}, acc ->
      if Map.has_key?(object, :profiles) do
        update_class_profiles(name, object, acc)
      else
        acc
      end
    end)
  end

  defp update_class_profiles(_name, object, classes) do
    case object[:_links] do
      nil ->
        classes

      links ->
        Enum.reduce(links, classes, fn {type, key, _}, acc ->
          case type do
            :class ->
              Map.update!(acc, String.to_atom(key), fn class ->
                Map.put(class, :profiles, merge_profiles(class[:profiles], object[:profiles]))
              end)

            _ ->
              acc
          end
        end)
    end
  end

  defp merge_profiles(nil, p2) do
    p2
  end

  defp merge_profiles(p1, nil) do
    p1
  end

  defp merge_profiles(p1, p2) do
    p1 ++ p2
  end

  defp update_dictionary(dictionary) do
    types = get_in(dictionary, [:types, :attributes])

    Map.update!(dictionary, :attributes, fn attributes ->
      Enum.into(attributes, %{}, fn {name, attribute} ->
        type = attribute[:type] || "object_t"

        attribute =
          case types[String.to_atom(type)] do
            nil ->
              attribute
              |> Map.put(:type, "object_t")
              |> Map.put(:object_type, type)

            _type ->
              attribute
          end

        {name, attribute}
      end)
    end)
  end

  defp error(message) do
    Logger.error(message)
    System.stop(1)
  end
end
