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

  @enforce_keys [
    :version,
    :profiles,
    :categories,
    :dictionary,
    :base_event,
    :classes,
    :all_classes,
    :objects
  ]
  defstruct ~w[version profiles dictionary base_event categories classes all_classes objects]a

  @type t() :: %__MODULE__{}
  @type class_t() :: map()
  @type object_t() :: map()
  @type category_t() :: map()
  @type dictionary_t() :: map()
  @type link_t() :: %{
          group: :common | :class | :object,
          type: String.t(),
          caption: String.t(),
          attribute_keys: nil | MapSet.t(String.t())
        }

  @ocsf_deprecated :"@deprecated"

  @doc """
  Load the schema files and initialize the cache.
  """
  @spec init() :: __MODULE__.t()
  def init() do
    version = JsonReader.read_version()

    categories = JsonReader.read_categories() |> update_categories()
    dictionary = JsonReader.read_dictionary() |> update_dictionary()

    {base_event, classes, all_classes} = read_classes(categories[:attributes])
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

    objects = update_observable_from_classes(classes, objects)

    base_event = final_check(:base_event, base_event, attributes)

    no_req_set = MapSet.new()
    {profiles, no_req_set} = fix_entities(profiles, no_req_set)
    {base_event, no_req_set} = fix_entity(base_event, no_req_set)
    {classes, no_req_set} = fix_entities(classes, no_req_set)
    {objects, no_req_set} = fix_entities(objects, no_req_set)

    if MapSet.size(no_req_set) > 0 do
      no_reqs = no_req_set |> Enum.sort() |> Enum.join(", ")

      Logger.warning(
        "The following attributes do not have a \"requirement\" field," <>
          " a value of \"optional\" will be used: #{no_reqs}"
      )
    end

    # Remove observable tracking properties (no longer needed)
    classes =
      Enum.into(classes, %{}, fn {class_key, class} ->
        {class_key, Map.delete(class, :parent_observables)}
      end)

    base_event = Map.delete(base_event, :parent_observables)

    objects =
      Enum.into(objects, %{}, fn {object_key, object} ->
        {object_key, Map.delete(object, :observable_inherited?)}
      end)

    %__MODULE__{
      version: version,
      profiles: profiles,
      categories: categories,
      dictionary: dictionary,
      base_event: base_event,
      classes: classes,
      all_classes: all_classes,
      objects: objects
    }
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

  @spec all_classes(__MODULE__.t()) :: map()
  def all_classes(%__MODULE__{all_classes: all_classes}), do: all_classes

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

  defp enrich(type, dictionary_attributes) do
    Map.update!(type, :attributes, fn list -> update_attributes(list, dictionary_attributes) end)
  end

  defp update_attributes(attributes, dictionary_attributes) do
    Enum.map(attributes, fn {name, attribute} ->
      case find_attribute(dictionary_attributes, name, attribute[:_source]) do
        nil ->
          Logger.warning("undefined attribute: #{name}: #{inspect(attribute)}")
          {name, attribute}

        base ->
          {name, Utils.deep_merge(base, attribute)}
      end
    end)
  end

  defp enrich_ex(type, dictionary_attributes, objects, ref_objects) do
    {attributes, ref_objects} =
      update_attributes_ex(type[:attributes], dictionary_attributes, objects, ref_objects)

    {Map.put(type, :attributes, attributes), ref_objects}
  end

  defp update_attributes_ex(attributes, dictionary_attributes, objects, ref_objects) do
    Enum.map_reduce(attributes, ref_objects, fn {name, attribute}, acc ->
      case find_attribute(dictionary_attributes, name, attribute[:_source]) do
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
              enrich_ex(
                objects[obj_type],
                dictionary_attributes,
                objects,
                Map.put(acc, obj_type, nil)
              )
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
      |> Enum.into(%{}, fn {class_key, class} ->
        {class_key, Map.put(class, :meta_type, :class)}
      end)
      |> Enum.into(%{}, fn class -> attribute_source(class) end)
      |> extend_type()

    validate_classes(classes)

    resolved = resolve_extends(classes)

    classes =
      resolved
      # remove intermediate hidden classes
      |> Stream.filter(fn {class_key, class} -> !hidden_class?(class_key, class) end)
      |> Enum.into(%{}, fn class -> enrich_class(class, categories) end)

    # all_classes has just enough info to interrogate the complete class hierarchy,
    # removing most details. It can be used to get the caption and parent (extends) of
    # any class, including hidden ones (classes without a uid)
    all_classes =
      Enum.map(
        resolved,
        fn {class_key, class} ->
          {class_key,
           Map.take(class, [:name, :caption, :extends])
           |> Map.put(:hidden?, hidden_class?(class_key, class))}
        end
      )
      |> Enum.into(%{})

    {Map.get(classes, :base_event), classes, all_classes}
  end

  defp validate_classes(classes) do
    for {class_key, class} <- classes do
      if Map.has_key?(class, :observables) and hidden_class?(class_key, class) do
        Logger.error(
          "Illegally defined \"observables\" in hidden class \"#{class_key}\". This" <>
            " would cause colliding definitions of the same observable type_id values in all" <>
            " extensions of this class." <>
            " Instead define observables in non-hidden extensions of \"#{class_key}\"."
        )

        System.stop(1)
      end
    end
  end

  defp read_objects() do
    objects = JsonReader.read_objects()
    validate_objects(objects)

    objects
    |> Enum.into(%{}, fn {object_key, object} ->
      {object_key, Map.put(object, :meta_type, :object)}
    end)
    |> resolve_extends()
    # removes abstract objects
    |> Stream.filter(fn {key, _o} -> !hidden_object?(key) end)
    |> Enum.into(%{}, fn obj -> attribute_source(obj) end)
    |> extend_type()
  end

  defp validate_objects(objects) do
    for {object_key, object} <- objects do
      if Map.has_key?(object, :observable) and hidden_object?(object[:name]) do
        Logger.error(
          "Illegally defined \"observable\" in hidden object \"#{object_key}\". This" <>
            " would cause colliding definitions of the same observable type_id value in all" <>
            " extensions of this object." <>
            " Instead define observable in non-hidden extensions of \"#{object_key}\"."
        )

        System.stop(1)
      end
    end
  end

  @spec hidden_object?(atom() | String.t()) :: boolean()
  def hidden_object?(object_name) when is_binary(object_name) do
    String.starts_with?(object_name, "_")
  end

  def hidden_object?(object_key) when is_atom(object_key) do
    hidden_object?(Atom.to_string(object_key))
  end

  @spec hidden_class?(atom(), map()) :: boolean()
  def hidden_class?(class_key, class) do
    class_key != :base_event and !Map.has_key?(class, :uid)
  end

  @spec hidden_class?(map()) :: boolean()
  def hidden_class?(class) do
    class[:name] != "base_event" and !Map.has_key?(class, :uid)
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
        # This is an extension class or object with the same name its own base class
        # (The name is not prefixed with the extension name, unlike a key / uid.)

        base_key = String.to_atom(name)

        Logger.info("#{key} #{item[:meta_type]} extends #{base_key}")

        case Map.get(items, base_key) do
          nil ->
            Logger.warning("#{key} #{item[:meta_type]} extends invalid item: #{base_key}")
            Map.put(acc, key, item)

          base ->
            profiles = merge(base[:profiles], item[:profiles])
            attributes = Utils.deep_merge(base[:attributes], item[:attributes])

            updated =
              base
              |> Map.put(:profiles, profiles)
              |> Map.put(:attributes, attributes)

            updated =
              if updated[:meta_type] == :class and
                   Map.has_key?(updated, :observables) and Map.has_key?(item, :observables) do
                Map.put(
                  updated,
                  :observables,
                  Utils.deep_merge(updated[:observables], item[:observables])
                )
              else
                updated
              end

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
            Logger.error("#{item[:name]} extends undefined item: #{extends}")
            System.stop(1)

          base ->
            base = resolve_extends(items, base)

            item = merge_class_observables(base, item)

            attributes =
              Utils.deep_merge(base[:attributes], item[:attributes])
              |> Enum.filter(fn {_name, attr} -> attr != nil end)
              |> Map.new()

            item = fix_object_observable(base, item)

            Map.merge(base, item, &merge_profiles/3)
            |> Map.put(:attributes, attributes)
        end
    end
  end

  defp merge_class_observables(base, item) do
    if item[:meta_type] == :class do
      item =
        if Map.has_key?(base, :observables) do
          Map.put(item, :parent_observables, base[:observables])
        else
          item
        end

      cond do
        Map.has_key?(base, :observables) and Map.has_key?(item, :observables) ->
          Map.put(item, :observables, Utils.deep_merge(base[:observables], item[:observables]))

        Map.has_key?(base, :observables) ->
          Map.put(item, :observables, base[:observables])

        true ->
          item
      end
    else
      # Not a class
      item
    end
  end

  defp fix_object_observable(base, item) do
    cond do
      item[:meta_type] != :object ->
        item

      Map.has_key?(item, :observable) ->
        # This object has assigned its own observable type_id,
        # which is either the first one assigned (in inheritance tree if there is one),
        # or this object is overriding a parent's observable type_id.
        # In either case, this means the observable mark isn't inherited,
        # thus we are clearing the flag (whether or not it is set).
        Map.put(item, :observable_inherited?, false)

      Map.has_key?(base, :observable) ->
        # The item object is inheriting the observable mark from its parent.
        Map.put(item, :observable_inherited?, true)

      true ->
        item
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
  defp fix_entities(entities, no_req_set) do
    Enum.reduce(
      entities,
      {Map.new(), no_req_set},
      fn {entity_name, entity}, {entities, no_req_set} ->
        {entity, no_req_set} = fix_entity(entity, no_req_set)
        {Map.put(entities, entity_name, entity), no_req_set}
      end
    )
  end

  # Final fix up of an entity definition map.
  # The term "entity" mean a single profile, object, class, or base_event (a special class).
  @spec fix_entity(map(), MapSet.t()) :: {map(), MapSet.t()}
  defp fix_entity(entity, no_req_set) do
    {attributes, no_req_set} = fix_attributes(entity[:attributes], no_req_set)
    {Map.put(entity, :attributes, attributes), no_req_set}
  end

  # Final fix up an attributes map.
  @spec fix_attributes(map(), MapSet.t()) :: {map(), MapSet.t()}
  defp fix_attributes(attributes, no_req_set) do
    Enum.reduce(
      attributes,
      {Map.new(), no_req_set},
      fn {attribute_name, attribute_details}, {attributes, no_req_set} ->
        {
          # The Map.put_new fixes the actual missing requirement problem
          Map.put(
            attributes,
            attribute_name,
            Map.put_new(attribute_details, :requirement, "optional")
          ),
          # This adds attributes with missing requirement to a set for later logging
          track_missing_requirement(attribute_name, attribute_details, no_req_set)
        }
      end
    )
  end

  @spec track_missing_requirement(String.t(), map(), MapSet.t()) :: MapSet.t()
  defp track_missing_requirement(attribute_name, attribute_details, no_req_set) do
    if Map.has_key?(attribute_details, :requirement) do
      no_req_set
    else
      context = "#{attribute_details[:_source]}.#{attribute_name}"

      if MapSet.member?(no_req_set, context) do
        no_req_set
      else
        MapSet.put(no_req_set, context)
      end
    end
  end

  defp update_observables(objects, dictionary) do
    if Map.has_key?(objects, :observable) do
      observable_attribute_types = get_in(dictionary, [:types, :attributes]) |> observables()
      observable_objects = observables(objects)
      observable_attributes = observables(dictionary[:attributes])

      Map.update!(objects, :observable, fn observable ->
        observable
        |> update_observable_type_id_enum(
          observable_attribute_types,
          fn _name, attribute -> "#{attribute[:caption]} (Type)" end
        )
        |> update_observable_type_id_enum(
          observable_objects,
          fn _name, object -> "#{object[:caption]} (Object)" end
        )
        |> update_observable_type_id_enum(
          observable_attributes,
          fn _name, attribute -> "#{attribute[:caption]} (Attribute)" end
        )
      end)
    else
      objects
    end
  end

  defp update_observable_type_id_enum(observable, entities, caption_fn) do
    update_in(observable, [:attributes, :type_id, :enum], fn enum ->
      new_enum = generate_observable_type_id_enum(entities, caption_fn)

      Map.merge(
        enum,
        new_enum,
        fn type_id, v1, v2 ->
          Logger.error(
            "Collision of observable type_id #{type_id} between \"#{v1[:caption]}\" and \"#{v2[:caption]}\" (detected while updating)"
          )

          System.stop(1)
          v1
        end
      )
    end)
  end

  defp generate_observable_type_id_enum(entities, caption_fn) do
    Enum.reduce(entities, %{}, fn {name, entity}, acc ->
      type_id = Integer.to_string(entity[:observable]) |> String.to_atom()
      caption = caption_fn.(name, entity)
      description = entity[:description]

      if Map.has_key?(acc, type_id) do
        Logger.error(
          "Collision of observable type_id #{type_id} between \"#{acc[type_id][:caption]}\" and \"#{caption}\" (detected while generating)"
        )

        System.stop(1)
      end

      Map.put(acc, type_id, %{caption: caption, description: description})
    end)
  end

  defp observables(list) do
    Enum.filter(list, fn {_key, value} ->
      Map.has_key?(value, :observable) and !value[:observable_inherited?]
    end)
  end

  defp update_observable_from_classes(classes, objects) do
    if Map.has_key?(objects, :observable) do
      observable =
        Enum.reduce(
          classes,
          objects[:observable],
          fn {_class_key, class}, observable ->
            if Map.has_key?(class, :observables) do
              update_observable_from_class(class, observable)
            else
              observable
            end
          end
        )

      Map.put(objects, :observable, observable)
    else
      objects
    end
  end

  defp update_observable_from_class(class, observable) do
    parent_observables = class[:parent_observables]

    update_in(observable, [:attributes, :type_id, :enum], fn enum ->
      new_enum =
        Enum.reduce(
          class[:observables],
          %{},
          fn {attribute_path, observable_type_id}, acc ->
            if parent_observables == nil or
                 parent_observables[attribute_path] != observable_type_id do
              type_id = Integer.to_string(observable_type_id) |> String.to_atom()
              caption = "#{class[:caption]} Class: #{attribute_path} (Class-Specific)"

              description =
                "Class-specific attribute on path \"#{attribute_path}\" for the #{class[:caption]} Class."

              if Map.has_key?(acc, type_id) do
                Logger.error(
                  "Collision of observable type_id #{type_id} between #{inspect(acc[type_id][:caption])} and \"#{caption}\" (detected while generating from class)"
                )

                System.stop(1)
              end

              Map.put(acc, type_id, %{caption: caption, description: description})
            else
              acc
            end
          end
        )

      Map.merge(
        enum,
        new_enum,
        fn type_id, v1, v2 ->
          Logger.error(
            "Collision of observable type_id #{type_id} between #{inspect(v1[:caption])} and #{inspect(v2[:caption])} (detected while updating from class)"
          )

          System.stop(1)
          v1
        end
      )
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

  defp update_linked_profiles(group, links, object, classes) do
    Enum.reduce(links, classes, fn link, acc ->
      if link[:group] == group do
        Map.update!(acc, String.to_atom(link[:type]), fn class ->
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
    dictionary =
      Map.update!(dictionary, :types, fn types ->
        Map.update!(types, :attributes, fn attributes ->
          Enum.into(attributes, %{}, fn {type_key, type} ->
            {type_key, Map.put(type, :meta_type, :dictionary_type)}
          end)
        end)
      end)

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

        {name, Map.put(attribute, :meta_type, :dictionary_attribute)}
      end)
    end)
  end

  defp update_profiles(profiles, dictionary_attributes) do
    Enum.into(profiles, %{}, fn {name, profile} ->
      {name,
       Map.update!(profile, :attributes, fn attributes ->
         update_profile(name, attributes, dictionary_attributes)
       end)}
    end)
  end

  defp update_profile(profile, attributes, dictionary_attributes) do
    Enum.into(attributes, %{}, fn {name, attribute} ->
      {name,
       case find_attribute(dictionary_attributes, name, String.to_atom(profile)) do
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
    |> copy(from, :meta_type)
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
