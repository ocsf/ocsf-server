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
    :parsed_version,
    :profiles,
    :categories,
    :dictionary,
    :base_event,
    :classes,
    :all_classes,
    :objects,
    :all_objects
  ]
  defstruct ~w[
    version
    parsed_version
    profiles
    dictionary
    base_event
    categories
    classes
    all_classes
    objects
    all_objects
  ]a

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
    parsed_version = Utils.parse_version(version[:version])

    if not is_map(parsed_version) do
      {:error, error_message, original_version} = parsed_version
      error("Schema version #{inspect(original_version)} is invalid: #{error_message}")
    end

    categories = JsonReader.read_categories() |> update_categories()
    dictionary = JsonReader.read_dictionary() |> update_dictionary()

    {base_event, classes, all_classes, observable_type_id_map} =
      read_classes(categories[:attributes])

    {objects, all_objects, observable_type_id_map} = read_objects(observable_type_id_map)

    dictionary = Utils.update_dictionary(dictionary, base_event, classes, objects)
    observable_type_id_map = observables_from_dictionary(dictionary, observable_type_id_map)

    dictionary_attributes = dictionary[:attributes]

    profiles = JsonReader.read_profiles() |> update_profiles(dictionary_attributes)

    # clean up the cached files
    JsonReader.cleanup()

    # Check profiles used in objects, adding objects to profile's _links
    profiles = Profiles.sanity_check(:object, objects, profiles)

    objects =
      objects
      |> Utils.update_objects(dictionary_attributes)
      |> update_observable(observable_type_id_map)
      |> update_objects()
      |> final_check(dictionary_attributes)

    # Check profiles used in classes, adding classes to profile's _links
    profiles = Profiles.sanity_check(:class, classes, profiles)

    classes =
      classes
      |> update_classes(objects)
      |> final_check(dictionary_attributes)

    base_event = final_check(:base_event, base_event, dictionary_attributes)

    no_req_set = MapSet.new()
    {profiles, no_req_set} = fix_entities(profiles, no_req_set, "profile")
    {base_event, no_req_set} = fix_entity(base_event, no_req_set, :base_event, "class")
    {classes, no_req_set} = fix_entities(classes, no_req_set, "class")
    {objects, no_req_set} = fix_entities(objects, no_req_set, "object")

    if MapSet.size(no_req_set) > 0 do
      no_reqs = no_req_set |> Enum.sort() |> Enum.join(", ")

      Logger.warning(
        "The following attributes do not have a \"requirement\" field," <>
          " a value of \"optional\" will be used: #{no_reqs}"
      )
    end

    %__MODULE__{
      version: version,
      parsed_version: parsed_version,
      profiles: profiles,
      categories: categories,
      dictionary: dictionary,
      base_event: base_event,
      classes: classes,
      all_classes: all_classes,
      objects: objects,
      all_objects: all_objects
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

  @spec parsed_version(__MODULE__.t()) :: Utils.version_or_error_t()
  def parsed_version(%__MODULE__{parsed_version: parsed_version}), do: parsed_version

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

  @spec all_objects(__MODULE__.t()) :: map()
  def all_objects(%__MODULE__{all_objects: all_objects}), do: all_objects

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
    attributes
    |> Enum.map(fn {name, attribute} ->
      case find_attribute(dictionary_attributes, name, attribute[:_source]) do
        nil ->
          Logger.warning("undefined attribute: #{name}: #{inspect(attribute)}")
          {name, attribute}

        base ->
          {name, Utils.deep_merge(base, attribute)}
      end
    end)
    |> Utils.add_sibling_of_to_attributes()
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
    classes = JsonReader.read_classes()

    observable_type_id_map = observables_from_classes(classes)

    classes =
      classes
      |> Enum.into(%{}, fn class_tuple -> attribute_source(class_tuple) end)
      |> patch_type("class")
      |> resolve_extends()

    # all_classes has just enough info to interrogate the complete class hierarchy,
    # removing most details. It can be used to get the caption and parent (extends) of
    # any class, including hidden ones.
    all_classes =
      Enum.map(
        classes,
        fn {class_key, class} ->
          class =
            class
            |> Map.take([:name, :caption, :extends, :extension])
            |> Map.put(:hidden?, hidden_class?(class_key, class))

          {class_key, class}
        end
      )
      |> Enum.into(%{})

    classes =
      classes
      # remove intermediate hidden classes
      |> Stream.filter(fn {class_key, class} -> !hidden_class?(class_key, class) end)
      |> Enum.into(%{}, fn class_tuple -> enrich_class(class_tuple, categories) end)

    {Map.get(classes, :base_event), classes, all_classes, observable_type_id_map}
  end

  defp read_objects(observable_type_id_map) do
    objects = JsonReader.read_objects()

    observable_type_id_map = observables_from_objects(observable_type_id_map, objects)

    objects =
      objects
      |> Enum.into(%{}, fn object_tuple -> attribute_source(object_tuple) end)
      |> patch_type("object")
      |> resolve_extends()

    # all_objects has just enough info to interrogate the complete object hierarchy,
    # removing most details. It can be used to get the caption and parent (extends) of
    # any object, including hidden ones
    all_objects =
      Enum.map(
        objects,
        fn {object_key, object} ->
          object =
            object
            |> Map.take([:name, :caption, :extends, :extension])
            |> Map.put(:hidden?, hidden_object?(object_key))

          {object_key, object}
        end
      )
      |> Enum.into(%{})

    objects =
      objects
      |> Stream.filter(fn {object_key, _object} -> !hidden_object?(object_key) end)
      |> Enum.into(%{})

    {objects, all_objects, observable_type_id_map}
  end

  @spec observables_from_classes(map()) :: map()
  defp observables_from_classes(classes) do
    Enum.reduce(
      classes,
      %{},
      fn {class_key, class}, observable_type_id_map ->
        validate_class_observables(class_key, class)

        observable_type_id_map
        |> observables_from_item_attributes(classes, class_key, class, "Class")
        |> observables_from_item_observables(classes, class_key, class, "Class")
      end
    )
  end

  defp validate_class_observables(class_key, class) do
    if Map.has_key?(class, :observable) do
      error(
        "Illegal definition of one or more attributes with \"#{:observable}\" in class" <>
          "  \"#{class_key}\". Defining class-level observables is not supported (this would be" <>
          " redundant). Instead use the \"class_uid\" attribute for querying, correlating, and" <>
          " reporting."
      )
    end

    if not patch_extends?(class) and hidden_class?(class_key, class) do
      if Map.has_key?(class, :attributes) and
           Enum.any?(
             class[:attributes],
             fn {_attribute_key, attribute} ->
               Map.has_key?(attribute, :observable)
             end
           ) do
        error(
          "Illegal definition of one or more attributes with \"#{:observable}\" definition in" <>
            " hidden class \"#{class_key}\". This would cause colliding definitions of the same" <>
            " observable type_id values in all children of this class. Instead define" <>
            " observables (of any kind) in non-hidden child classes of \"#{class_key}\"."
        )
      end

      if Map.has_key?(class, :observables) do
        error(
          "Illegal \"#{:observables}\" definition in hidden class \"#{class_key}\". This" <>
            " would cause colliding definitions of the same observable type_id values in" <>
            " all children of this class. Instead define observables (of any kind) in" <>
            " non-hidden child classes of \"#{class_key}\"."
        )
      end
    end
  end

  @spec observables_from_item_attributes(map(), map(), atom(), map(), String.t()) :: map()
  defp observables_from_item_attributes(observable_type_id_map, items, item_key, item, kind) do
    {caption, _description} = find_item_caption_and_description(items, item_key, item)

    if Map.has_key?(item, :attributes) do
      Enum.reduce(
        item[:attributes],
        observable_type_id_map,
        fn {attribute_key, attribute}, observable_type_id_map ->
          if Map.has_key?(attribute, :observable) do
            observable_type_id = Utils.observable_type_id_to_atom(attribute[:observable])

            if Map.has_key?(observable_type_id_map, observable_type_id) do
              error(
                "Collision of observable type_id #{observable_type_id} between" <>
                  " \"#{caption}\" #{kind} attribute \"#{attribute_key}\" and" <>
                  " \"#{observable_type_id_map[observable_type_id][:caption]}\""
              )

              observable_type_id_map
            else
              observable_kind = "#{kind}-Specific Attribute"

              Map.put(
                observable_type_id_map,
                observable_type_id,
                make_observable_enum_entry(
                  "#{caption} #{kind}: #{attribute_key}",
                  "#{kind}-specific attribute \"#{attribute_key}\" for the #{caption} #{kind}.",
                  observable_kind
                )
              )
            end
          else
            observable_type_id_map
          end
        end
      )
    else
      observable_type_id_map
    end
  end

  @spec observables_from_item_observables(map(), map(), atom(), map(), String.t()) :: map()
  defp observables_from_item_observables(observable_type_id_map, items, item_key, item, kind) do
    {caption, _description} = find_item_caption_and_description(items, item_key, item)

    if Map.has_key?(item, :observables) do
      Enum.reduce(
        item[:observables],
        observable_type_id_map,
        fn {attribute_path, observable_type_id}, observable_type_id_map ->
          observable_type_id = Utils.observable_type_id_to_atom(observable_type_id)

          if(Map.has_key?(observable_type_id_map, observable_type_id)) do
            error(
              "Collision of observable type_id #{observable_type_id} between" <>
                " \"#{caption}\" #{kind} attribute path \"#{attribute_path}\" and" <>
                " \"#{observable_type_id_map[observable_type_id][:caption]}\""
            )

            observable_type_id_map
          else
            observable_kind = "#{kind}-Specific Attribute"

            Map.put(
              observable_type_id_map,
              observable_type_id,
              make_observable_enum_entry(
                "#{caption} #{kind}: #{attribute_path}",
                "#{kind}-specific attribute \"#{attribute_path}\" for the #{caption} #{kind}.",
                observable_kind
              )
            )
          end
        end
      )
    else
      observable_type_id_map
    end
  end

  @spec observables_from_objects(map(), map()) :: map()
  defp observables_from_objects(observable_type_id_map, objects) do
    Enum.reduce(
      objects,
      observable_type_id_map,
      fn {object_key, object}, observable_type_id_map ->
        validate_object_observables(object_key, object)

        observable_type_id_map
        |> observable_from_object(objects, object_key, object)
        |> observables_from_item_attributes(objects, object_key, object, "Object")

        # Not supported: |> observables_from_item_observables(objects, object_key, object, "Object")
      end
    )
  end

  defp validate_object_observables(object_key, object) do
    if Map.has_key?(object, :observables) do
      # Attribute-path observables would be tricky to implement as an machine-driven enrichment.
      # It would require tracking the relative from the point of the object down that tree of an
      # overall OCSF event.
      error(
        "Illegal \"#{:observables}\" definition in object \"#{object_key}\"." <>
          " Object-specific attribute path observables are not supported." <>
          " Please file an issue if you find this feature necessary."
      )
    end

    if not patch_extends?(object) and hidden_object?(object[:name]) do
      if Map.has_key?(object, :attributes) and
           Enum.any?(
             object[:attributes],
             fn {_attribute_key, attribute} ->
               Map.has_key?(attribute, :observable)
             end
           ) do
        error(
          "Illegal definition of one or more attributes with \"#{:observable}\" in hidden object" <>
            " \"#{object_key}\". This would cause colliding definitions of the same" <>
            " observable type_id values in all children of this object. Instead define" <>
            " observables (of any kind) in non-hidden child objects of \"#{object_key}\"."
        )
      end

      if Map.has_key?(object, :observable) do
        error(
          "Illegal \"#{:observable}\" definition in hidden object \"#{object_key}\". This" <>
            " would cause colliding definitions of the same observable type_id values in" <>
            " all children of this object. Instead define observables (of any kind) in" <>
            " non-hidden child objects of \"#{object_key}\"."
        )
      end
    end
  end

  @spec observable_from_object(map(), map(), atom(), map()) :: map()
  defp observable_from_object(observable_type_id_map, objects, object_key, object) do
    {caption, description} = find_item_caption_and_description(objects, object_key, object)

    if Map.has_key?(object, :observable) do
      observable_type_id = Utils.observable_type_id_to_atom(object[:observable])

      if(Map.has_key?(observable_type_id_map, observable_type_id)) do
        error(
          "Collision of observable type_id #{observable_type_id} between" <>
            " \"#{caption}\" Object \"#{:observable}\" and" <>
            " \"#{observable_type_id_map[observable_type_id][:caption]}\""
        )

        observable_type_id_map
      else
        Map.put(
          observable_type_id_map,
          observable_type_id,
          make_observable_enum_entry(caption, description, "Object")
        )
      end
    else
      observable_type_id_map
    end
  end

  defp observables_from_dictionary(dictionary, observable_type_id_map) do
    observable_type_id_map
    |> observables_from_dictionary_items(dictionary[:types][:attributes], "Dictionary Type")
    |> observables_from_dictionary_items(dictionary[:attributes], "Dictionary Attribute")
  end

  defp observables_from_dictionary_items(observable_type_id_map, items, kind) do
    if items do
      Enum.reduce(
        items,
        observable_type_id_map,
        fn {_item_key, item}, observable_type_id_map ->
          if Map.has_key?(item, :observable) do
            observable_type_id = Utils.observable_type_id_to_atom(item[:observable])

            if Map.has_key?(observable_type_id_map, observable_type_id) do
              error(
                "Collision of observable type_id #{observable_type_id} between #{kind}" <>
                  " \"#{item[:caption]}\" and" <>
                  " \"#{observable_type_id_map[observable_type_id][:caption]}\""
              )

              observable_type_id_map
            else
              Map.put(
                observable_type_id_map,
                observable_type_id,
                make_observable_enum_entry(item[:caption], item[:description], kind)
              )
            end
          else
            observable_type_id_map
          end
        end
      )
    else
      observable_type_id_map
    end
  end

  # make an observable type_id enum entry
  @spec make_observable_enum_entry(String.t(), String.t(), String.t()) :: map()
  defp make_observable_enum_entry(caption, description, observable_kind) do
    %{
      caption: caption,
      description: "Observable by #{observable_kind}.<br>#{description}",
      _observable_kind: observable_kind
    }
  end

  @spec find_item_caption_and_description(map(), atom(), map() | nil) :: {String.t(), String.t()}
  defp find_item_caption_and_description(items, item_key, item)
       when is_map(items) and is_atom(item_key) do
    cond do
      item == nil ->
        caption = Atom.to_string(item_key)
        {caption, caption}

      patch_extends?(item) ->
        find_item_parent_caption_and_description(items, item_key, item)

      item[:caption] != nil ->
        caption = item[:caption]
        {caption, item[:description] || caption}

      item[:extends] != nil ->
        find_item_parent_caption_and_description(items, item_key, item)

      true ->
        caption = Atom.to_string(item_key)
        {caption, caption}
    end
  end

  @spec find_item_parent_caption_and_description(map(), atom(), map() | nil) ::
          {String.t(), String.t()}
  defp find_item_parent_caption_and_description(items, item_key, item)
       when is_map(items) and is_atom(item_key) do
    {parent_key, parent_item} = Utils.find_parent(items, item[:extends], item[:extension])

    if parent_key do
      find_item_caption_and_description(items, parent_key, parent_item)
    else
      caption = Atom.to_string(item_key)
      {caption, caption}
    end
  end

  @spec hidden_object?(atom() | String.t()) :: boolean()
  defp hidden_object?(object_name) when is_binary(object_name) do
    String.starts_with?(object_name, "_")
  end

  defp hidden_object?(object_key) when is_atom(object_key) do
    hidden_object?(Atom.to_string(object_key))
  end

  @spec hidden_class?(atom(), map()) :: boolean()
  defp hidden_class?(class_key, class) do
    class_key != :base_event and !Map.has_key?(class, :uid)
  end

  # Add category_uid, class_uid, and type_uid
  defp enrich_class({class_key, class}, categories) do
    class =
      class
      |> update_class_uid(categories)
      |> add_type_uid(class_key)
      |> add_class_uid(class_key)
      |> add_category_uid(class_key, categories)

    {class_key, class}
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

    class =
      if category != nil do
        class
        |> Map.put(:category, Atom.to_string(key))
        |> Map.put(:category_name, category[:caption])
      else
        class
      end

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
        Logger.warning("class \"#{name}\" has no activity_id nor disposition_id")
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
    category_name = class[:category]

    {_key, category} = Utils.find_entity(categories, class, class[:category])

    if category == nil do
      case category_name do
        "other" ->
          Logger.info("Class \"#{class[:name]}\" uses special undefined category \"other\"")

        nil ->
          Logger.warning("Class \"#{class[:name]}\" has no category")

        undefined ->
          Logger.warning("Class \"#{class[:name]}\" has undefined category: #{undefined}")
      end

      # Match update_class_uid and use 0 for undefined categories
      Map.put(class, :category_uid, 0)
    else
      category_uid = category[:uid]

      class
      |> Map.put(:category_uid, category_uid)
      |> update_in(
        [:attributes, :category_uid, :enum],
        fn _enum ->
          id = Integer.to_string(category_uid) |> String.to_atom()
          %{id => category}
        end
      )
      |> put_in(
        [:attributes, :category_name, :description],
        "The event category name, as defined by category_uid value:" <>
          " <code>#{category[:caption]}</code>."
      )
    end
    |> put_in([:attributes, :category_uid, :_source], name)
  end

  # Adds :_source key to each attribute of item. This must be done before processing (compiling)
  # inheritance and patching (resolve_extends and patch_type) since after that processing the
  # original source is lost.
  defp attribute_source({item_key, item}) do
    item =
      Map.update(
        item,
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
                if patch_extends?(item) do
                  # Because attribute_source done before patching with patch_type, we need to
                  # capture the final "patched" type for use by the UI when displaying the source.
                  # Other uses of :_source require the original pre-patched source.
                  {
                    key,
                    attribute
                    |> Map.put(:_source, item_key)
                    |> Map.put(:_source_patched, String.to_atom(item[:extends]))
                  }
                else
                  {key, Map.put(attribute, :_source, item_key)}
                end
            end
          )
        end
      )

    {item_key, item}
  end

  defp patch_type(items, kind) do
    Enum.reduce(items, %{}, fn {key, item}, acc ->
      # Logger.debug(fn ->
      #   patching? =
      #     if patch_extends?(item) do
      #       "    PATCHING:"
      #     else
      #       "not patching:"
      #     end

      #   "#{patching?} key #{inspect(key)}," <>
      #     " name #{inspect(item[:name])}, extends #{inspect(item[:extends])}," <>
      #     " caption #{inspect(item[:caption])}, extension #{inspect(item[:extension])}"
      # end)

      if patch_extends?(item) do
        # This is an extension class or object with the same name its own base class
        # (The name is not prefixed with the extension name, unlike a key / uid.)

        name = item[:extends]

        base_key = String.to_atom(name)

        Logger.info("#{key} #{kind} is patching #{base_key}")

        # First check the accumulator in case the same object is extended by multiple extensions,
        # that way the previous modifications are taken into account
        case Map.get(acc, base_key, Map.get(items, base_key)) do
          nil ->
            error("#{key} #{kind} attempted to patch invalid item: #{base_key}")
            acc

          base ->
            profiles = merge_profiles(base[:profiles], item[:profiles])
            attributes = Utils.deep_merge(base[:attributes], item[:attributes])

            patched_base =
              base
              |> Map.put(:profiles, profiles)
              |> Map.put(:attributes, attributes)
              # Top-level observable.
              # Only occurs in objects, but is safe to do for classes too.
              |> Utils.put_non_nil(:observable, item[:observable])
              # Top-level path-based observables.
              # Only occurs in classes, but is safe to do for objects too.
              |> Utils.put_non_nil(:observables, item[:observables])
              |> Utils.put_non_nil(:references, item[:references])
              |> patch_constraints(item)

            Map.put(acc, base_key, patched_base)
        end
      else
        Map.put_new(acc, key, item)
      end
    end)
  end

  # Is this item a special patch extends definition as done by patch_type.
  # It is triggered by a class or object that has no name or the name is the same as the extends.
  defp patch_extends?(item) do
    extends = item[:extends]

    if extends do
      name = item[:name]

      if name do
        if name == extends do
          # name and extends are the same
          true
        else
          # true if name matches extends without extension scope ("extension/name" -> "name")
          # This when an item in one extension patches an item in another.
          name == Utils.descope(extends)
        end
      else
        # extends with no name
        true
      end
    else
      false
    end
  end

  defp patch_constraints(base, item) do
    if Map.has_key?(item, :constraints) do
      constraints = item[:constraints]

      if constraints != nil and !Enum.empty?(constraints) do
        Map.put(base, :constraints, constraints)
      else
        Map.delete(base, :constraints)
      end
    else
      base
    end
  end

  defp resolve_extends(items) do
    Enum.map(items, fn {item_key, item} -> {item_key, resolve_extends(items, item)} end)
  end

  defp resolve_extends(items, item) do
    case item[:extends] do
      nil ->
        item

      extends ->
        {_parent_key, parent_item} = Utils.find_parent(items, extends, item[:extension])

        case parent_item do
          nil ->
            error("#{inspect(item[:name])} extends undefined item: #{inspect(extends)}")

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
  defp merge_profiles(:profiles, nil, v2), do: v2
  defp merge_profiles(:profiles, v1, v2), do: Enum.concat(v1, v2) |> Enum.uniq()
  defp merge_profiles(_profiles, v1, nil), do: v1
  defp merge_profiles(_profiles, _v1, v2), do: v2

  # Final fix up a map of many name -> entity key-value pairs.
  # The term "entities" means to profiles, objects, or classes.
  @spec fix_entities(map(), MapSet.t(), String.t()) :: {map(), MapSet.t()}
  defp fix_entities(entities, no_req_set, kind) do
    Enum.reduce(
      entities,
      {Map.new(), no_req_set},
      fn {entity_key, entity}, {entities, no_req_set} ->
        {entity, no_req_set} = fix_entity(entity, no_req_set, entity_key, kind)
        {Map.put(entities, entity_key, entity), no_req_set}
      end
    )
  end

  # Final fix up of an entity definition map.
  # The term "entity" mean a single profile, object, class, or base_event (a special class).
  @spec fix_entity(map(), MapSet.t(), atom(), String.t()) :: {map(), MapSet.t()}
  defp fix_entity(entity, no_req_set, entity_key, kind) do
    attributes = entity[:attributes]

    if attributes do
      {attributes, no_req_set} =
        Enum.reduce(
          attributes,
          {%{}, no_req_set},
          fn {attribute_name, attribute_details}, {attributes, no_req_set} ->
            {
              # The Map.put_new fixes the actual missing requirement problem
              Map.put(
                attributes,
                attribute_name,
                Map.put_new(attribute_details, :requirement, "optional")
              ),
              # This adds attributes with missing requirement to a set for later logging
              track_missing_requirement(
                attribute_name,
                attribute_details,
                no_req_set,
                entity_key,
                kind
              )
            }
          end
        )

      {Map.put(entity, :attributes, attributes), no_req_set}
    else
      {entity, no_req_set}
    end
  end

  @spec track_missing_requirement(atom(), map(), MapSet.t(), atom(), String.t()) :: MapSet.t()
  defp track_missing_requirement(attribute_key, attribute, no_req_set, entity_key, kind) do
    if Map.has_key?(attribute, :requirement) do
      no_req_set
    else
      context = "#{entity_key}.#{attribute_key} (#{kind})"

      if MapSet.member?(no_req_set, context) do
        no_req_set
      else
        MapSet.put(no_req_set, context)
      end
    end
  end

  defp update_observable(objects, observable_type_id_map) do
    if Map.has_key?(objects, :observable) do
      update_in(objects, [:observable, :attributes, :type_id, :enum], fn enum_map ->
        Map.merge(enum_map, observable_type_id_map, fn observable_type_id, enum1, enum2 ->
          error(
            "Collision of observable type_id #{observable_type_id} between" <>
              " \"#{enum1[:caption]}\" and \"#{enum2[:caption]}\" (detected while merging)"
          )

          enum1
        end)
      end)
    else
      objects
    end
  end

  defp final_check(maps, dictionary) do
    Enum.into(maps, %{}, fn {name, map} ->
      {name, final_check(name, map, dictionary)}
    end)
  end

  defp final_check(name, map, dictionary) do
    profiles = map[:profiles]
    attributes = map[:attributes]

    list =
      Enum.reduce(attributes, [], fn {key, attribute}, acc ->
        missing_desc_warning(attribute[:description], name, key, dictionary)
        add_datetime(find_attribute(dictionary, key, attribute[:_source]), key, attribute, acc)
      end)

    update_profiles(list, map, profiles, attributes)
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

  defp add_datetime(nil, _key, _attribute, acc) do
    acc
  end

  defp add_datetime(v, key, attribute, acc) do
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
    |> Map.put(:profiles, merge_profiles(profiles, ["datetime"]))
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
          Map.put(class, :profiles, merge_profiles(class[:profiles], object[:profiles]))
        end)
      else
        acc
      end
    end)
  end

  defp merge_profiles(nil, p2) do
    p2
  end

  defp merge_profiles(p1, nil) do
    p1
  end

  defp merge_profiles(p1, p2) do
    Enum.concat(p1, p2) |> Enum.uniq()
  end

  defp update_dictionary(dictionary) do
    types = get_in(dictionary, [:types, :attributes])

    Map.update!(dictionary, :attributes, fn attributes ->
      Enum.into(attributes, %{}, fn {attribute_key, attribute} ->
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

        {attribute_key, attribute}
      end)
    end)
  end

  # Flesh out profile attributes from dictionary attributes
  defp update_profiles(profiles, dictionary_attributes) do
    Enum.into(profiles, %{}, fn {name, profile} ->
      {name,
       Map.update!(profile, :attributes, fn attributes ->
         update_profile(name, attributes, dictionary_attributes)
       end)}
    end)
  end

  defp update_profile(profile, profile_attributes, dictionary_attributes) do
    Enum.into(profile_attributes, %{}, fn {name, attribute} ->
      {name,
       case find_attribute(dictionary_attributes, name, String.to_atom(profile)) do
         nil ->
           Logger.warning("profile #{profile} uses #{name} that is not defined in the dictionary")
           attribute

         dictionary_attribute ->
           update_profile_attribute(attribute, dictionary_attribute)
       end
       |> Map.delete(:profile)}
    end)
  end

  defp update_profile_attribute(to, from) do
    to
    |> copy_new(from, :caption)
    |> copy_new(from, :description)
    |> copy_new(from, :is_array)
    |> copy_new(from, :enum)
    |> copy_new(from, :type)
    |> copy_new(from, :type_name)
    |> copy_new(from, :object_name)
    |> copy_new(from, :object_type)
    |> copy_new(from, :observable)
    |> copy_new(from, :source)
    |> copy_new(from, :references)
    |> copy_new(from, :sibling)
    |> copy_new(from, :"@deprecated")
  end

  defp copy_new(to, from, key) do
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
