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
  alias Schema.Profiles
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

  @ocsf_deprecated :"@deprecated"

  @doc """
  Load the schema files and initialize the cache.
  """
  @spec init() :: __MODULE__.t()
  def init() do
    version = JsonReader.read_version()

    categories = JsonReader.read_categories() |> update_categories()
    dictionary = JsonReader.read_dictionary() |> update_dictionary()

    {base_event, classes} = read_classes(categories[:attributes])
    objects = read_objects()

    dictionary = Utils.update_dictionary(dictionary, base_event, classes, objects)
    attributes = dictionary[:attributes]

    profiles = JsonReader.read_profiles() |> update_profiles(attributes)

    # clean up the cached files
    JsonReader.cleanup()

    # Apply profiles to objects and classes
    {objects, profiles} = Profiles.sanity_check(:object, objects, profiles)

    objects =
      objects
      |> Utils.update_objects(attributes)
      |> update_observables(dictionary)
      |> update_objects()
      |> final_check(attributes)

    {classes, profiles} = Profiles.sanity_check(:class, classes, profiles)

    classes =
      update_classes(classes, objects)
      |> final_check(attributes)

    base_event = final_check(:base_event, base_event, attributes)

    log_context = MapSet.new()
    {profiles, log_context} = fix_entities(profiles, log_context)
    {base_event, log_context} = fix_entity(base_event, log_context)
    {classes, log_context} = fix_entities(classes, log_context)
    {objects, _} = fix_entities(objects, log_context)

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
    Enum.into(classes, Map.new(), fn {name, class} ->
      {name, enrich(class, dictionary[:attributes])}
    end)
  end

  @spec export_base_event(__MODULE__.t()) :: map()
  def export_base_event(%__MODULE__{base_event: base_event, dictionary: dictionary}) do
    enrich(base_event, dictionary[:attributes])
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

  @doc """
  Returns extended class definition, which includes all objects referred by the class.
  """
  @spec class_ex(__MODULE__.t(), atom()) :: nil | class_t()
  def class_ex(
        %__MODULE__{dictionary: dictionary, objects: objects, base_event: base_event},
        :base_event
      ) do
    class_ex(base_event, dictionary, objects)
  end

  def class_ex(%__MODULE__{dictionary: dictionary, classes: classes, objects: objects}, id) do
    Map.get(classes, id) |> class_ex(dictionary, objects)
  end

  defp class_ex(nil, _dictionary, _objects) do
    nil
  end

  defp class_ex(class, dictionary, objects) do
    {class_ex, ref_objects} = enrich_ex(class, dictionary[:attributes], objects, Map.new())
    Map.put(class_ex, :objects, Map.to_list(ref_objects))
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
    Enum.into(objects, Map.new(), fn {name, object} ->
      {name, enrich(object, dictionary[:attributes])}
    end)
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

  @spec object_ex(__MODULE__.t(), any) :: nil | object_t()
  def object_ex(%__MODULE__{dictionary: dictionary, objects: objects}, id) do
    case Map.get(objects, id) do
      nil ->
        nil

      object ->
        {object_ex, ref_objects} = enrich_ex(object, dictionary[:attributes], objects, Map.new())
        Map.put(object_ex, :objects, Map.to_list(ref_objects))
    end
  end

  defp enrich(type, dictionary) do
    Map.update!(type, :attributes, fn list -> update_attributes(list, dictionary) end)
  end

  defp update_attributes(attributes, dictionary) do
    Enum.map(attributes, fn {name, attribute} ->
      case find_attribute(dictionary, name, attribute[:_source]) do
        nil ->
          Logger.warning("undefined attribute: #{name}: #{inspect(attribute)}")
          {name, attribute}

        base ->
          {name, Utils.deep_merge(base, attribute)}
      end
    end)
  end

  defp enrich_ex(type, dictionary, objects, ref_objects) do
    {attributes, ref_objects} =
      update_attributes_ex(type[:attributes], dictionary, objects, ref_objects)

    {Map.put(type, :attributes, attributes), ref_objects}
  end

  defp update_attributes_ex(attributes, dictionary, objects, ref_objects) do
    Enum.map_reduce(attributes, ref_objects, fn {name, attribute}, acc ->
      case find_attribute(dictionary, name, attribute[:_source]) do
        nil ->
          Logger.warning("undefined attribute: #{name}: #{inspect(attribute)}")
          {{name, attribute}, acc}

        base ->
          attribute =
            Utils.deep_merge(base, attribute)
            |> Map.delete(:_links)

          update_attributes_ex(
            attribute[:object_type],
            name,
            attribute,
            fn obj_type ->
              enrich_ex(objects[obj_type], dictionary, objects, Map.put(acc, obj_type, nil))
            end,
            acc
          )
      end
    end)
  end

  defp update_attributes_ex(nil, name, attribute, _enrich, acc) do
    {{name, attribute}, acc}
  end

  defp update_attributes_ex(object_name, name, attribute, enrich, acc) do
    obj_type = String.to_atom(object_name)

    acc =
      if Map.has_key?(acc, obj_type) do
        acc
      else
        {object, acc} = enrich.(obj_type)
        Map.put(acc, obj_type, object)
      end

    {{name, attribute}, acc}
  end

  defp find_attribute(dictionary, name, source) do
    case Atom.to_string(source) |> String.split("/") do
      [_] ->
        dictionary[name]

      [ext, _] ->
        ext_name = String.to_atom("#{ext}/#{name}")
        dictionary[ext_name] || dictionary[name]

      _ ->
        Logger.warning("#{name} has an invalid source: #{source}")
        dictionary[name]
    end
  end

  defp read_classes(categories) do
    classes =
      JsonReader.read_classes()
      |> Enum.into(%{}, fn class -> attribute_source(class) end)
      |> extend_type()

    classes =
      resolve_extends(classes)
      # remove intermediate classes
      |> Stream.filter(fn {key, class} -> Map.has_key?(class, :uid) or key == :base_event end)
      |> Enum.into(%{}, fn class -> enrich_class(class, categories) end)

    {Map.get(classes, :base_event), classes}
  end

  defp read_objects() do
    JsonReader.read_objects()
    |> resolve_extends()
    # removes abstract objects
    |> Stream.filter(fn {key, _o} -> !String.starts_with?(Atom.to_string(key), "_") end)
    |> Enum.into(%{}, fn obj -> attribute_source(obj) end)
    |> extend_type()
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
      Enum.into(attributes, Map.new(), fn {name, cat} ->
        update_category_uid(name, cat, cat[:extension_id])
      end)
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

    cat_uid = category[:uid] || 0
    class_uid = class[:uid] || 0

    try do
      case class[:extension_id] do
        nil ->
          Map.put(class, :uid, Types.class_uid(cat_uid, class_uid))

        ext ->
          Map.put(class, :uid, Types.class_uid(Types.category_uid_ex(ext, cat_uid), class_uid))
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
        Logger.warning("class '#{name}' has no activity_id nor disposition_id")
        %{}

      values ->
        enum_values(class_uid, caption, values)
    end
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
    for {key, val} = _value <- values, into: %{} do
      {
        make_enum_id(class_uid, key),
        Map.put(val, :caption, Types.type_name(caption, val[:caption]))
      }
    end
  end

  defp make_enum_id(class_uid, key) do
    integer_to_id(class_uid, String.to_integer(Atom.to_string(key)))
  end

  defp integer_to_id(class_uid, id) do
    Integer.to_string(class_uid + id) |> String.to_atom()
  end

  defp add_class_uid(data, name) do
    class_name = data[:caption]

    class_uid =
      data[:uid]
      |> Integer.to_string()
      |> String.to_atom()

    enum = %{
      :caption => class_name,
      :description => data[:description]
    }

    data
    |> put_in([:attributes, :class_uid, :enum], %{class_uid => enum})
    |> put_in([:attributes, :class_uid, :_source], name)
    |> put_in(
      [:attributes, :class_name, :description],
      "The event class name, as defined by class_uid value: <code>#{class_name}</code>."
    )
  end

  defp add_category_uid(class, name, categories) do
    case class[:category] do
      nil ->
        Logger.warning("class '#{class[:name]}' has no category")
        class

      "other" ->
        class

      cat_name ->
        {_key, category} = Utils.find_entity(categories, class, cat_name)

        if category == nil do
          Logger.warning("class '#{class[:name]}' has an invalid category: #{cat_name}")
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
        |> put_in(
          [:attributes, :category_name, :description],
          "The event category name, as defined by category_uid value: <code>#{category[:caption]}</code>."
        )
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
            fn
              {key, nil} ->
                {key, nil}

              {key, attribute} ->
                {key, Map.put(attribute, :_source, name)}
            end
          )
        end
      )

    {name, data}
  end

  defp extend_type(items) do
    Enum.reduce(items, %{}, fn {key, item}, acc ->
      name = item[:name] || item[:extends]

      if name == item[:extends] do
        base_key = String.to_atom(name)

        Logger.info("#{key} extends #{base_key}")

        case Map.get(items, base_key) do
          nil ->
            Logger.warning("#{key} extends invalid item: #{base_key}")
            Map.put(acc, key, item)

          base ->
            profiles = merge(base[:profiles], item[:profiles])
            attributes = Utils.deep_merge(base[:attributes], item[:attributes])

            updated =
              base
              |> Map.put(:profiles, profiles)
              |> Map.put(:attributes, attributes)

            Map.put(acc, base_key, updated)
        end
      else
        Map.put_new(acc, key, item)
      end
    end)
  end

  defp resolve_extends(items) do
    Enum.map(items, fn {name, item} -> {name, resolve_extends(items, item)} end)
  end

  defp resolve_extends(items, item) do
    case item[:extends] do
      nil ->
        item

      extends ->
        case find_super_class(items, item, extends) do
          nil ->
            exit("Error: #{item[:name]} extends undefined item: #{extends}")

          base ->
            base = resolve_extends(items, base)

            attributes =
              Utils.deep_merge(base[:attributes], item[:attributes])
              |> Enum.filter(fn {_name, attr} -> attr != nil end)
              |> Map.new()

            Map.merge(base, item, &merge_profiles/3)
            |> Map.put(:attributes, attributes)
        end
    end
  end

  defp merge_profiles(:profiles, v1, nil), do: v1
  defp merge_profiles(:profiles, v1, v2), do: Enum.concat(v1, v2) |> Enum.uniq()
  defp merge_profiles(_profiles, _v1, v2), do: v2

  defp find_super_class(classes, class, extends) do
    case Map.get(classes, String.to_atom(extends)) do
      nil ->
        case class[:extension] do
          nil ->
            Map.get(classes, String.to_atom(extends))

          extension ->
            case Map.get(classes, Utils.to_uid(extension, extends)) do
              nil -> Map.get(classes, String.to_atom(extends))
              other -> other
            end
        end

      base ->
        base
    end
  end

  # Final fix up a map of many name -> entity key-value pairs.
  # The term "entities" means to profiles, objects, or classes.
  @spec fix_entities(map(), MapSet.t()) :: {map(), MapSet.t()}
  defp fix_entities(entities, log_context) do
    Enum.reduce(
      entities,
      {Map.new(), log_context},
      fn ({entity_name, entity}, {entities, log_context}) ->
        {entity, log_context} = fix_entity(entity, log_context)
        {Map.put(entities, entity_name, entity), log_context}
      end
    )
  end

  # Final fix up of an entity definition map.
  # The term "entity" mean a single profile, object, class, or base_event (a special class).
  @spec fix_entity(map(), MapSet.t()) :: {map(), MapSet.t()}
  defp fix_entity(entity, log_context) do
    {attributes, log_context} = fix_attributes(entity[:attributes], log_context)
    {Map.put(entity, :attributes, attributes), log_context}
  end

  # Final fix up an attributes map.
  @spec fix_attributes(map(), MapSet.t) :: {map(), MapSet.t}
  defp fix_attributes(attributes, log_context) do
    Enum.reduce(
      attributes,
      {Map.new(), log_context},
      fn ({attribute_name, attribute_details}, {attributes, log_context}) ->
        {
          Map.put(attributes, attribute_name, Map.put_new(attribute_details, :requirement, "optional")),
          log_requirement(attribute_name, attribute_details, log_context)
        }
      end)
  end

  @spec log_requirement(String.t(), map(), MapSet.t()) :: MapSet.t()
  defp log_requirement(attribute_name, attribute_details, log_context) do
    if Map.has_key?(attribute_details, :requirement) do
      log_context
    else
      source = attribute_details[:_source]
      context = "#{source}:#{attribute_name}"
      if MapSet.member?(log_context, context) do
        log_context
      else
        Logger.warning("Attribute \"#{attribute_name}\" from \"#{source}\"" <>
          " does not have \"requirement\", \"optional\" will be used")
        MapSet.put(log_context, context)
      end
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
    Enum.reduce(types, %{}, fn {_name, type}, acc ->
      k = Integer.to_string(type[:observable]) |> String.to_atom()
      v = %{caption: type[:caption], description: type[:description]}

      case type[:extends] do
        nil ->
          Map.put(acc, k, v)

        "object" ->
          Map.put(acc, k, v)

        "_entity" ->
          Map.put(acc, k, v)

        _ ->
          acc
      end
    end)
  end

  defp observables(list) do
    Enum.filter(list, fn {_, value} ->
      Map.get(value, :observable, 0) > 0
    end)
  end

  defp final_check(maps, dictionary) do
    Enum.into(maps, %{}, fn {name, map} ->
      deprecated_type(name, map, Map.get(map, @ocsf_deprecated))

      {name, final_check(name, map, dictionary)}
    end)
  end

  defp deprecated_type(_name, _map, nil) do
  end

  defp deprecated_type(name, map, deprecated) do
    type =
      if Map.has_key?(map, :category) do
        "class"
      else
        "object"
      end

    message = Map.get(deprecated, :message)
    Logger.warning("The #{name} #{type} has been deprecated. #{message}")
  end

  defp final_check(name, map, dictionary) do
    profiles = map[:profiles]
    attributes = map[:attributes]

    list =
      Enum.reduce(attributes, [], fn {key, attribute}, acc ->
        deprecated_warning(name, key, attribute)
        missing_desc_warning(attribute[:description], name, key, dictionary)
        add_datetime(Utils.find_entity(dictionary, map, key), key, attribute, acc)
      end)

    update_profiles(list, map, profiles, attributes)
  end

  defp deprecated_warning(name, key, attribute) do
    case Map.get(attribute, @ocsf_deprecated) do
      nil ->
        :ok

      deprecated ->
        Logger.warning(
          "The #{key} attribute in #{name} has been deprecated. #{Map.get(deprecated, :message)}"
        )
    end
  end

  defp missing_desc_warning(nil, name, key, dictionary) do
    desc = get_in(dictionary, [key, :description]) || ""

    if String.contains?(desc, "See specific usage") do
      Logger.warning("Please update the description for #{name}.#{key}: #{desc}")
    end
  end

  defp missing_desc_warning(_desc, _name, _key, _dict) do
    :ok
  end

  defp add_datetime({_k, nil}, _key, _attribute, acc) do
    acc
  end

  defp add_datetime({_k, v}, key, attribute, acc) do
    case Map.get(v, :type) do
      "timestamp_t" ->
        attribute =
          attribute
          |> Map.put(:profile, "datetime")
          |> Map.put(:requirement, "optional")

        [{Utils.make_datetime(key), attribute} | acc]

      _ ->
        acc
    end
  end

  defp update_profiles([], map, _profiles, _attributes) do
    map
  end

  defp update_profiles(list, map, profiles, attributes) do
    # add the synthetic datetime profile
    map
    |> Map.put(:profiles, merge(profiles, ["datetime"]))
    |> Map.put(:attributes, Enum.into(list, attributes))
  end

  defp update_objects(objects) do
    Enum.reduce(objects, objects, fn {_name, object}, acc ->
      if Map.has_key?(object, :profiles) do
        update_object_profiles(object, acc)
      else
        acc
      end
    end)
  end

  defp update_object_profiles(object, objects) do
    case object[:_links] do
      nil ->
        objects

      links ->
        update_linked_profiles(:object, links, object, objects)
    end
  end

  defp update_classes(classes, objects) do
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
        update_linked_profiles(:class, links, object, classes)
    end
  end

  defp update_linked_profiles(name, links, object, classes) do
    Enum.reduce(links, classes, fn {type, key, _}, acc ->
      if type == name do
        Map.update!(acc, String.to_atom(key), fn class ->
          Map.put(class, :profiles, merge(class[:profiles], object[:profiles]))
        end)
      else
        acc
      end
    end)
  end

  defp merge(nil, p2) do
    p2
  end

  defp merge(p1, nil) do
    p1
  end

  defp merge(p1, p2) do
    Enum.concat(p1, p2) |> Enum.uniq()
  end

  defp update_dictionary(dictionary) do
    types = get_in(dictionary, [:types, :attributes])

    Map.update!(dictionary, :attributes, fn attributes ->
      Enum.into(attributes, %{}, fn {name, attribute} ->
        type = attribute[:type] || "object_t"

        {name,
         case types[String.to_atom(type)] do
           nil ->
             attribute
             |> Map.put(:type, "object_t")
             |> Map.put(:object_type, type)

           _type ->
             attribute
         end}
      end)
    end)
  end

  defp update_profiles(profiles, dictionary) do
    Enum.into(profiles, %{}, fn {name, profile} ->
      {name,
       Map.update!(profile, :attributes, fn attributes ->
         update_profile(name, attributes, dictionary)
       end)}
    end)
  end

  defp update_profile(profile, attributes, dictionary) do
    Enum.into(attributes, %{}, fn {name, attribute} ->
      {name,
       case find_attribute(dictionary, name, String.to_atom(profile)) do
         nil ->
           Logger.warning("profile #{profile} uses #{name} that is not defined in the dictionary")
           attribute

         attr ->
           copy(attribute, attr)
       end
       |> Map.delete(:profile)}
    end)
  end

  defp copy(to, from) do
    to
    |> copy(from, :caption)
    |> copy(from, :description)
    |> copy(from, :is_array)
    |> copy(from, :enum)
    |> copy(from, :type)
    |> copy(from, :type_name)
    |> copy(from, :object_name)
    |> copy(from, :object_type)
  end

  defp copy(to, from, key) do
    case from[key] do
      nil -> to
      val -> Map.put_new(to, key, val)
    end
  end

  defp error(message) do
    Logger.error(message)
    System.stop(1)
  end
end
