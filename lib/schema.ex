# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema do
  @moduledoc """
  Schema keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  alias Schema.SingleRepo
  alias Schema.Utils
  require Logger

  @dialyzer :no_improper_lists

  @doc """
  Returns the schema version string.
  """
  @spec version() :: String.t()
  def version() do
    SingleRepo.version()
  end

  @spec parsed_version() :: Utils.version_t()
  def parsed_version() do
    SingleRepo.parsed_version()
  end

  @spec server_version() :: String.t()
  def server_version() do
    Application.spec(:schema_server)
    |> Keyword.get(:vsn)
    |> to_string()
    |> String.trim_trailing("-SNAPSHOT")
  end

  @doc """
  Returns the entire schema. Useful for pages making a lot of iteretive calls that need schema
  information.
  """
  @spec schema() :: map()
  def schema() do
    SingleRepo.schema()
  end

  @doc """
  Returns the entire clean schema, without browser information. Useful for API handlers that
  make many iterative calls that needs schema information.
  """
  @spec schema() :: map()
  def clean_schema() do
    SingleRepo.clean_schema()
  end

  @doc """
  Returns the data types themselves (without the top level types caption, description, etc.).
  """
  @spec clean_data_types_attributes() :: any
  def clean_data_types_attributes() do
    SingleRepo.clean_dictionary()[:types][:attributes]
  end

  @doc """
  Returns the schema extensions.
  """
  @spec extensions() :: map()
  def extensions() do
    # Note: SingleRepo.extensions() and SingleRepo.clean_extensions() return the same data.
    #       The difference is intent, with "clean" being ideal for APIs.
    SingleRepo.extensions()
  end

  @doc """
  Returns the schema extensions.
  """
  @spec clean_extensions() :: map()
  def clean_extensions() do
    # Note: SingleRepo.extensions() and SingleRepo.clean_extensions() return the same data.
    #       The difference is intent, with "clean" being ideal for APIs.
    SingleRepo.clean_extensions()
  end

  @doc """
  Returns the schema profiles without browser information.
  """
  @spec clean_profiles() :: map()
  def clean_profiles() do
    SingleRepo.clean_profiles()
  end

  @doc """
  Returns the schema profiles filtered, with browser information.
  """
  @spec profiles_filter_extensions(Utils.string_set_t() | nil) :: map()
  def profiles_filter_extensions(extensions) do
    SingleRepo.profiles() |> Utils.filter_items_by_extensions(extensions)
  end

  @doc """
  Returns the schema profiles filtered, without browser information.
  """
  @spec clean_profiles_filter_extensions(Utils.string_set_t() | nil) :: map()
  def clean_profiles_filter_extensions(extensions) do
    SingleRepo.clean_profiles() |> Utils.filter_items_by_extensions(extensions)
  end

  @doc """
  Reloads the event schema without the extensions.
  """
  @spec reload() :: :ok
  def reload() do
    SingleRepo.reload()
  end

  @doc """
  Reloads the event schema with extensions from the given path.
  """
  @spec reload(String.t() | list()) :: :ok
  def reload(path) do
    SingleRepo.reload(path)
  end

  @doc """
  Returns the event categories defined in the given extension set.
  """
  @spec clean_categories_filter_extensions(Utils.string_set_t() | nil) :: map()
  def clean_categories_filter_extensions(extensions) do
    schema = SingleRepo.clean_schema()

    schema[:categories]
    |> Map.update!(:attributes, fn attributes ->
      Utils.filter_items_by_extensions(attributes, extensions)
      |> Enum.into(%{}, fn {category_name, _category} ->
        {
          category_name,
          category_with_classes_filter_extension(schema, Utils.to_uid(category_name), extensions)
        }
      end)
    end)
  end

  @spec clean_category_filter_extensions(
          atom(),
          Utils.string_set_t() | nil
        ) :: nil | Utils.category_t()
  def clean_category_filter_extensions(id, extensions) do
    category_with_classes_filter_extension(SingleRepo.clean_schema(), id, extensions)
  end

  @doc """
  Returns the attribute dictionary.
  """
  @spec dictionary() :: Utils.dictionary_t()
  def dictionary() do
    SingleRepo.dictionary()
  end

  @doc """
  Returns the attribute dictionary including the extension.
  Used for the dictionary attributes page.
  """
  @spec dictionary_filter_extensions(Utils.string_set_t(), map()) :: Utils.dictionary_t()
  def dictionary_filter_extensions(extensions, schema) do
    schema[:dictionary]
    |> Map.update!(:attributes, fn attributes ->
      Utils.filter_items_by_extensions(attributes, extensions)
    end)
  end

  @doc """
  Returns the attribute dictionary including the extension, without browser information.
  """
  @spec clean_dictionary_filter_extensions(Utils.string_set_t()) :: Utils.dictionary_t()
  def clean_dictionary_filter_extensions(extensions) do
    SingleRepo.clean_dictionary()
    |> Map.update!(:attributes, fn attributes ->
      Utils.filter_items_by_extensions(attributes, extensions)
    end)
  end

  @doc """
  Returns the data types defined in dictionary. Used for data types page.
  """
  @spec data_types() :: map()
  def data_types() do
    SingleRepo.dictionary()[:types]
  end

  @doc """
  Parameter 1 must be the actual data types as from Schema.clean_data_types_attributes/0.
  Returns true if parameter 2 (type) is valid against parameter 3 (base type)
  """
  @spec data_type?(map(), String.t(), String.t() | list(String.t())) :: boolean()
  def data_type?(_data_types, type, type) do
    true
  end

  def data_type?(data_types, type, base_type) when is_binary(base_type) do
    case Map.get(data_types, String.to_atom(type)) do
      nil -> false
      data -> data[:type] == base_type
    end
  end

  def data_type?(data_types, type, base_types) do
    case Map.get(data_types, String.to_atom(type)) do
      nil ->
        false

      data ->
        t = data[:type] || type
        Enum.any?(base_types, fn b -> b == t end)
    end
  end

  @doc """
  Returns all event classes.
  """
  @spec classes() :: map()
  def classes() do
    SingleRepo.classes()
  end

  @doc """
  Returns all event classes (with browser information) filtered by extensions.
  This is meant for the classes HTML page, which needs browser-only metadata such
  as :_supersedes. Mirrors objects_filter_extensions/1.
  """
  @spec classes_filter_extensions(Utils.string_set_t() | nil) :: map()
  def classes_filter_extensions(extensions) do
    SingleRepo.classes() |> Utils.filter_items_by_extensions(extensions)
  end

  @spec clean_classes_filter_extensions(Utils.string_set_t() | nil) :: map()
  def clean_classes_filter_extensions(extensions) do
    SingleRepo.clean_classes() |> Utils.filter_items_by_extensions(extensions)
  end

  @doc """
  Returns clean classes (without browser information) filtered by extensions and profiles.
  This is meant for APIs. When profiles is nil, attributes are not filtered by profiles.
  """
  @spec clean_classes_filter_extensions_profiles(
          Utils.string_set_t() | nil,
          Utils.string_set_t() | nil
        ) :: map()
  def clean_classes_filter_extensions_profiles(extensions, profiles) do
    clean_classes_filter_extensions(extensions)
    |> Utils.filter_items_attributes_by_profiles(profiles)
  end

  @spec all_classes() :: map()
  def all_classes() do
    SingleRepo.all_classes()
  end

  @spec all_objects() :: map()
  def all_objects() do
    SingleRepo.all_objects()
  end

  @doc """
  Returns a single event class.
  """
  @spec class(atom() | String.t()) :: nil | Utils.class_t()
  def class(id) do
    SingleRepo.clean_classes()[Utils.to_uid(id)]
  end

  @doc """
  Returns class with attributes filtered by profiles.
  This is meant for the class page. When profiles is nil, it is treated like an empty set.
  """
  @spec class_filter_profiles(
          map(),
          atom(),
          Utils.string_set_t() | nil
        ) :: nil | map()
  def class_filter_profiles(schema, id, nil) do
    schema[:classes][id]
  end

  def class_filter_profiles(schema, id, profiles) do
    case schema[:classes][id] do
      nil ->
        nil

      class ->
        if profiles do
          Utils.filter_item_attributes_by_profiles(class, profiles)
        else
          Utils.filter_item_attributes_by_profiles(class, MapSet.new([]))
        end
    end
  end

  @doc """
  Returns class with attributes filtered by profiles, without browser info.
  This is meant for APIs. When profiles is nil, attributes are not filtered by profiles.
  """
  @spec clean_class_filter_profiles(
          atom(),
          Utils.string_set_t() | nil
        ) :: nil | map()
  def clean_class_filter_profiles(id, nil) do
    SingleRepo.clean_classes()[id]
  end

  def clean_class_filter_profiles(id, profiles) do
    case SingleRepo.clean_classes()[id] do
      nil ->
        nil

      class ->
        Utils.filter_item_attributes_by_profiles(class, profiles)
    end
  end

  @doc """
  Finds a class by the class uid value.
  """
  @spec find_class(integer()) :: nil | Utils.class_t()
  def find_class(uid) when is_integer(uid) do
    case Enum.find(SingleRepo.clean_classes(), fn {_, class} -> class[:uid] == uid end) do
      {_, class} -> class
      nil -> nil
    end
  end

  @spec objects_filter_extensions(Utils.string_set_t() | nil) :: map()
  def objects_filter_extensions(extensions) do
    SingleRepo.objects() |> Utils.filter_items_by_extensions(extensions)
  end

  @spec clean_objects_filter_extensions(Utils.string_set_t() | nil) :: map()
  def clean_objects_filter_extensions(extensions) do
    SingleRepo.clean_objects() |> Utils.filter_items_by_extensions(extensions)
  end

  @doc """
  Returns a single object.
  """
  @spec object(atom | String.t()) :: nil | Utils.object_t()
  def object(id) do
    SingleRepo.clean_objects()[Utils.to_uid(id)]
  end

  @spec object_filter_extensions(
          map(),
          atom(),
          Utils.string_set_t() | nil
        ) :: nil | map()
  defp object_filter_extensions(schema, id, extensions) do
    schema[:objects][id]
    |> Utils.filter_item_links_by_extensions(extensions)
  end

  @doc """
  Returns object filtered by extensions and profiles.
  This is meant for the object page. When profiles is nil, it is treated same as an empty set.
  """
  @spec object_filter_extensions_profiles(
          map(),
          atom(),
          Utils.string_set_t() | nil,
          Utils.string_set_t() | nil
        ) :: nil | map()
  def object_filter_extensions_profiles(schema, id, extensions, profiles) do
    case object_filter_extensions(schema, id, extensions) do
      nil ->
        nil

      object ->
        if profiles do
          Utils.filter_item_attributes_by_profiles(object, profiles)
        else
          Utils.filter_item_attributes_by_profiles(object, MapSet.new([]))
        end
    end
  end

  @spec clean_object_filter_extensions(atom(), Utils.string_set_t() | nil) :: nil | map()
  defp clean_object_filter_extensions(id, extensions) do
    SingleRepo.clean_objects()[id]
    |> Utils.filter_item_links_by_extensions(extensions)
  end

  @doc """
  Returns object filtered by extensions and profiles.
  This is meant for APIs. When profiles is nil, attributes are not filtered by profiles.
  """
  @spec clean_object_filter_extensions_profiles(
          atom(),
          Utils.string_set_t() | nil,
          Utils.string_set_t() | nil
        ) :: nil | map()
  def clean_object_filter_extensions_profiles(id, extensions, nil) do
    clean_object_filter_extensions(id, extensions)
  end

  def clean_object_filter_extensions_profiles(id, extensions, profiles) do
    case clean_object_filter_extensions(id, extensions) do
      nil ->
        nil

      object ->
        Utils.filter_item_attributes_by_profiles(object, profiles)
    end
  end

  # ---------------------------------------------- #
  # Class and object with referenced objects       #
  # as used by JSON Schema generation and graphs   #
  # ---------------------------------------------- #

  @doc """
  Returns class with referenced objects, with attributes filtered by profiles.
  This is meant for APIs. When profiles is nil, attributes are not filtered by profiles.
  """
  @spec class_with_referenced_objects_filter_profiles(
          atom(),
          Utils.string_set_t() | nil
        ) :: nil | map()
  def class_with_referenced_objects_filter_profiles(id, profiles) do
    schema = SingleRepo.clean_schema()
    objects = schema[:objects]

    case schema[:classes][id] do
      nil ->
        nil

      class ->
        class
        |> Utils.filter_item_attributes_by_profiles(profiles)
        |> Map.put(
          :objects,
          referenced_objects(class, objects)
          |> Utils.filter_items_attributes_by_profiles(profiles)
        )
    end
  end

  @doc """
  Returns object with referenced objects, and with attributes filtered by extensions and profiles.
  When profiles is nil, attributes are not filtered by profiles.
  """
  @spec object_with_referenced_objects_filter_extensions_profiles(
          atom(),
          Utils.string_set_t() | nil,
          Utils.string_set_t() | nil
        ) :: nil | map()
  def object_with_referenced_objects_filter_extensions_profiles(
        id,
        extensions,
        profiles
      ) do
    schema = SingleRepo.clean_schema()
    objects = schema[:objects]

    case schema[:objects][id] do
      nil ->
        nil

      object ->
        object
        |> Map.put(:objects, referenced_objects(object, objects))
        |> Utils.filter_item_links_by_extensions(extensions)
        |> Utils.filter_item_attributes_by_profiles(profiles)
    end
  end

  @spec referenced_objects(map(), map()) :: list()
  defp referenced_objects(item, schema_objects) do
    # Referenced objects are returned as a list so JsonSchema.encode_objects can pattern
    # match on an empty list (pattern matching on %{} matches _all_ maps)
    Enum.to_list(gather_referenced_objects(item, schema_objects, %{}))
  end

  @spec gather_referenced_objects(map(), map(), map()) :: map()
  defp gather_referenced_objects(item, schema_objects, referenced_objects) do
    Enum.reduce(
      item[:attributes],
      referenced_objects,
      fn {_attribute_name, attribute}, referenced_objects ->
        case attribute[:object_type] do
          nil ->
            referenced_objects

          object_type ->
            object_name = String.to_atom(object_type)

            if Map.has_key?(referenced_objects, object_name) do
              referenced_objects
            else
              object = schema_objects[object_name]
              referenced_objects = Map.put(referenced_objects, object_name, object)
              gather_referenced_objects(object, schema_objects, referenced_objects)
            end
        end
      end
    )
  end

  # ------------------#
  # Export Functions #
  # ------------------#

  @spec legacy_export_convert(map(), String.t()) :: map()
  defp legacy_export_convert(items, kind) do
    Enum.reduce(items, %{}, fn {item_name, item}, items ->
      Map.put(items, item_name, legacy_export_convert_attributes(item, kind, item_name))
    end)
  end

  @spec legacy_export_convert_attributes(map(), String.t(), atom()) :: map()
  defp legacy_export_convert_attributes(item, kind, item_name) do
    Map.update(item, :attributes, %{}, fn attributes ->
      Enum.reduce(attributes, %{}, fn {attribute_name, attribute}, attributes ->
        attribute =
          case attribute[:profiles] do
            nil ->
              attribute

            [profile] ->
              Map.put(attribute, :profile, profile)

            profiles ->
              raise "Cannot export in the legacy format. #{kind} \"#{item_name}\"" <>
                      " attribute \"#{attribute_name}\" is invoked by multiple" <>
                      " profiles: #{inspect(profiles)}. The legacy format only supports one."
          end

        Map.put(attributes, attribute_name, attribute)
      end)
    end)
  end

  @spec legacy_export_schema(
          Utils.string_set_t() | nil,
          Utils.string_set_t() | nil
        ) :: %{
          base_event: map(),
          classes: map(),
          objects: map(),
          types: map(),
          dictionary_attributes: map(),
          version: String.t()
        }
  def legacy_export_schema(extensions, profiles) do
    schema = SingleRepo.clean_schema()

    classes =
      schema[:classes]
      |> Utils.filter_clean_items_by_extensions(extensions)
      |> Utils.filter_items_attributes_by_profiles(profiles)
      |> legacy_export_convert("Class")

    objects =
      schema[:objects]
      |> Utils.filter_clean_items_by_extensions(extensions)
      |> Utils.filter_items_attributes_by_profiles(profiles)
      |> legacy_export_convert("Object")

    dictionary_attributes =
      Utils.filter_clean_items_by_extensions(schema[:dictionary][:attributes], extensions)

    %{
      base_event: classes[:base_event],
      classes: classes,
      objects: objects,
      types: schema[:dictionary][:types][:attributes],
      dictionary_attributes: dictionary_attributes,
      version: schema[:version]
    }
  end

  @spec legacy_export_classes(
          Utils.string_set_t() | nil,
          Utils.string_set_t() | nil
        ) :: map()
  def legacy_export_classes(extensions, nil) do
    SingleRepo.clean_classes()
    |> Utils.filter_clean_items_by_extensions(extensions)
    |> legacy_export_convert("Class")
  end

  def legacy_export_classes(extensions, profiles) do
    SingleRepo.clean_classes()
    |> Utils.filter_clean_items_by_extensions(extensions)
    |> Utils.filter_items_attributes_by_profiles(profiles)
    |> legacy_export_convert("Class")
  end

  @spec legacy_export_base_event(Utils.string_set_t() | nil) :: map()
  def legacy_export_base_event(nil) do
    SingleRepo.clean_classes()[:base_event]
    |> legacy_export_convert_attributes("Class", :base_event)
  end

  def legacy_export_base_event(profiles) do
    SingleRepo.clean_classes()[:base_event]
    |> Utils.filter_item_attributes_by_profiles(profiles)
    |> legacy_export_convert_attributes("Class", :base_event)
  end

  @spec legacy_export_objects(
          Utils.string_set_t(),
          Utils.string_set_t() | nil
        ) :: map()
  def legacy_export_objects(extensions, nil) do
    SingleRepo.clean_objects()
    |> Utils.filter_clean_items_by_extensions(extensions)
    |> legacy_export_convert("Object")
  end

  def legacy_export_objects(extensions, profiles) do
    SingleRepo.clean_objects()
    |> Utils.filter_clean_items_by_extensions(extensions)
    |> Utils.filter_items_attributes_by_profiles(profiles)
    |> legacy_export_convert("Object")
  end

  @spec export_schema() :: map()
  def export_schema() do
    # Clean schema is almost exactly what we want to match the modern output of the
    # ocsf-schema-compiler, _except_ profiles contain attributes.
    Map.update!(
      SingleRepo.clean_schema(),
      :profiles,
      fn profiles ->
        Enum.reduce(
          profiles,
          %{},
          fn {profile_name, profile}, profiles ->
            Map.put(profiles, profile_name, Map.delete(profile, :attributes))
          end
        )
      end
    )
  end

  # ----------------------------#
  # Enrich Event Data Functions #
  # ----------------------------#

  def enrich(data, enum_text, observables) do
    Schema.Helper.enrich(data, enum_text, observables)
  end

  # -------------------------------#
  # Generate Sample Data Functions #
  # -------------------------------#

  @doc """
  Returns a randomly generated sample event, based on the spcified profiles.
  """
  @spec generate_event(Utils.class_t(), Utils.string_set_t() | nil) :: map()
  def generate_event(class, profiles) when is_map(class) do
    Schema.Generator.generate_sample_event(class, profiles)
  end

  @doc """
  Returns randomly generated sample object data.
  """
  @spec generate_object(Utils.object_t() | atom() | binary()) :: any()
  def generate_object(type) when is_map(type) do
    Schema.Generator.generate_sample_object(type, nil)
  end

  def generate_object(type) do
    Schema.object(type) |> Schema.Generator.generate_sample_object(nil)
  end

  @doc """
  Returns randomly generated sample object data, based on the spcified profiles.
  """
  @spec generate_object(Utils.object_t(), Utils.string_set_t() | nil) :: map()
  def generate_object(type, profiles) when is_map(type) do
    Schema.Generator.generate_sample_object(type, profiles)
  end

  @spec category_with_classes_filter_extension(
          map(),
          atom(),
          Utils.string_set_t() | nil
        ) :: map() | nil
  defp category_with_classes_filter_extension(schema, id, extensions) do
    case schema[:categories][:attributes][id] do
      nil ->
        nil

      category ->
        classes =
          schema[:classes]
          |> Utils.filter_items_by_extensions(extensions)
          |> Map.delete(:attributes)
          |> Map.delete(:associations)

        category_uid = Atom.to_string(id)

        classes_list =
          classes
          |> Stream.filter(fn {_name, class} ->
            cat = Map.get(class, :category)
            cat == category_uid or Utils.to_uid(cat) == id
          end)
          |> Stream.map(fn {name, class} ->
            class =
              class
              |> Map.delete(:category)
              |> Map.delete(:category_name)

            {name, class}
          end)
          |> Enum.to_list()

        category
        |> Map.put(:name, category_uid)
        # Change classes_list to a map while reducing each class
        |> Map.put(
          :classes,
          Enum.into(classes_list, %{}, fn {name, class} ->
            {name, reduce_class(class)}
          end)
        )
    end
  end

  @spec reduce_class(map) :: map
  def reduce_class(data) do
    data
    |> delete_attributes()
    |> delete_associations()
  end

  @spec delete_attributes(map) :: map
  def delete_attributes(data) do
    Map.delete(data, :attributes)
  end

  @spec delete_associations(map) :: map
  defp delete_associations(data) do
    Map.delete(data, :associations)
  end
end
