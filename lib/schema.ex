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
  alias Schema.Repo
  alias Schema.Cache
  alias Schema.Utils

  @dialyzer :no_improper_lists

  @doc """
    Returns the schema version string.
  """
  @spec version :: String.t()
  def version(), do: Repo.version()

  @spec build_version :: String.t()
  def build_version() do
    Application.spec(:schema_server)
    |> Keyword.get(:vsn)
    |> to_string()
    |> String.trim_trailing("-SNAPSHOT")
  end

  @doc """
    Returns the schema extensions.
  """
  @spec extensions :: map()
  def extensions(), do: Cache.extensions()

  @doc """
    Returns the schema profiles.
  """
  @spec profiles :: map()
  def profiles(), do: Repo.profiles()

  @spec profiles(Repo.extensions_t()) :: map()
  def profiles(extensions) do
    Repo.profiles(extensions)
  end

  @doc """
    Reloads the event schema without the extensions.
  """
  @spec reload() :: :ok
  def reload(), do: Repo.reload()

  @doc """
    Reloads the event schema with extensions from the given path.
  """
  @spec reload(String.t() | list()) :: :ok
  def reload(path), do: Repo.reload(path)

  @doc """
    Returns the event categories.
  """
  @spec categories :: map()
  def categories(), do: Repo.categories()

  @doc """
    Returns the event categories defined in the given extension set.
  """
  def categories(extensions) do
    Map.update(Repo.categories(extensions), :attributes, %{}, fn attributes ->
      Enum.into(attributes, %{}, fn {name, _category} ->
        {name, category(extensions, name)}
      end)
    end)
  end

  @doc """
    Returns a single category with its classes.
  """
  @spec category(atom | String.t()) :: nil | Cache.category_t()
  def category(id), do: get_category(Utils.to_uid(id))

  @spec category(Repo.extensions_t(), String.t()) :: nil | Cache.category_t()
  def category(extensions, id), do: get_category(extensions, Utils.to_uid(id))

  @spec category(Repo.extensions_t(), String.t(), String.t()) :: nil | Cache.category_t()
  def category(extensions, extension, id),
    do: get_category(extensions, Utils.to_uid(extension, id))

  @doc """
    Returns the attribute dictionary.
  """
  @spec dictionary() :: Cache.dictionary_t()
  def dictionary(), do: Repo.dictionary()

  @doc """
    Returns the attribute dictionary including the extension.
  """
  @spec dictionary(Repo.extensions_t()) :: Cache.dictionary_t()
  def dictionary(extensions), do: Repo.dictionary(extensions)

  @doc """
    Returns the data types defined in dictionary.
  """
  @spec data_types :: map()
  def data_types(), do: Repo.data_types()

  @spec data_type?(binary(), binary() | list(binary())) :: boolean()
  def data_type?(type, type), do: true

  def data_type?(type, base_type) when is_binary(base_type) do
    types = Map.get(Repo.data_types(), :attributes)

    case Map.get(types, String.to_atom(type)) do
      nil -> false
      data -> data[:type] == base_type
    end
  end

  def data_type?(type, base_types) do
    types = Map.get(Repo.data_types(), :attributes)

    case Map.get(types, String.to_atom(type)) do
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
  def classes(), do: Repo.classes()

  @spec classes(Repo.extensions_t()) :: map()
  def classes(extensions), do: Repo.classes(extensions)

  @spec classes(Repo.extensions_t(), Repo.profiles_t()) :: map()
  def classes(extensions, profiles) do
    extensions
    |> Repo.classes()
    |> apply_profiles(profiles, MapSet.size(profiles))
  end

  @spec all_classes() :: map()
  def all_classes(), do: Repo.all_classes()

  @doc """
    Returns a single event class.
  """
  @spec class(atom() | String.t()) :: nil | Cache.class_t()
  def class(id), do: Repo.class(Utils.to_uid(id))

  @spec class(nil | String.t(), String.t()) :: nil | map()
  def class(extension, id),
    do: Repo.class(Utils.to_uid(extension, id))

  @spec class(String.t() | nil, String.t(), Repo.profiles_t() | nil) :: nil | map()
  def class(extension, id, nil), do: class(extension, id)

  def class(extension, id, profiles) do
    case class(extension, id) do
      nil ->
        nil

      class ->
        Map.update!(class, :attributes, fn attributes ->
          Utils.apply_profiles(attributes, profiles)
        end)
    end
  end

  @doc """
    Returns a single event class with the embedded objects.
  """
  @spec class_ex(atom() | String.t()) :: nil | Cache.class_t()
  def class_ex(id),
    do: Repo.class_ex(Utils.to_uid(id))

  @spec class_ex(nil | String.t(), String.t()) :: nil | map()
  def class_ex(extension, id),
    do: Repo.class_ex(Utils.to_uid(extension, id))

  @spec class_ex(String.t() | nil, String.t(), Repo.profiles_t() | nil) :: nil | map()
  def class_ex(extension, id, nil),
    do: class_ex(extension, id)

  def class_ex(extension, id, profiles) do
    case class_ex(extension, id) do
      nil ->
        nil

      class ->
        Schema.Profiles.apply_profiles(class, profiles)
    end
  end

  @doc """
  Finds a class by the class uid value.
  """
  @spec find_class(integer()) :: nil | Cache.class_t()
  def find_class(uid) when is_integer(uid), do: Repo.find_class(uid)

  @doc """
    Returns all objects.
  """
  @spec objects() :: map()
  def objects(), do: Repo.objects()

  @spec objects(Repo.extensions_t()) :: map()
  def objects(extensions), do: Repo.objects(extensions)

  @spec objects(Repo.extensions_t(), Repo.profiles_t()) :: map()
  def objects(extensions, profiles) do
    extensions
    |> Repo.objects()
    |> apply_profiles(profiles, MapSet.size(profiles))
  end

  @doc """
    Returns a single object.
  """
  @spec object(atom | String.t()) :: nil | Cache.object_t()
  def object(id),
    do: Repo.object(Utils.to_uid(id))

  @spec object(nil | String.t(), String.t()) :: nil | map()
  def object(extension, id) when is_binary(id) do
    Repo.object(Utils.to_uid(extension, id))
  end

  @spec object(Repo.extensions_t(), String.t(), String.t()) :: nil | map()
  def object(extensions, extension, id) when is_binary(id) do
    Repo.object(extensions, Utils.to_uid(extension, id))
  end

  @spec object(Repo.extensions_t(), String.t(), String.t(), Repo.profiles_t() | nil) ::
          nil | map()
  def object(extensions, extension, id, nil),
    do: object(extensions, extension, id)

  def object(extensions, extension, id, profiles) do
    case object(extensions, extension, id) do
      nil ->
        nil

      object ->
        Map.update!(object, :attributes, fn attributes ->
          Utils.apply_profiles(attributes, profiles)
        end)
    end
  end

  @doc """
    Returns a single object and with the embedded objects.
  """
  @spec object_ex(atom | String.t()) :: nil | Cache.object_t()
  def object_ex(id),
    do: Repo.object_ex(Utils.to_uid(id))

  @spec object_ex(nil | String.t(), String.t()) :: nil | map()
  def object_ex(extension, id) when is_binary(id) do
    Repo.object_ex(Utils.to_uid(extension, id))
  end

  @spec object_ex(Repo.extensions_t(), String.t(), String.t()) :: nil | map()
  def object_ex(extensions, extension, id) when is_binary(id) do
    Repo.object_ex(extensions, Utils.to_uid(extension, id))
  end

  @spec object_ex(Repo.extensions_t(), String.t(), String.t(), Repo.profiles_t() | nil) ::
          nil | map()
  def object_ex(extensions, extension, id, nil),
    do: object_ex(extensions, extension, id)

  def object_ex(extensions, extension, id, profiles) do
    case object_ex(extensions, extension, id) do
      nil ->
        nil

      object ->
        Map.update!(object, :attributes, fn attributes ->
          Utils.apply_profiles(attributes, profiles)
        end)
    end
  end

  # ------------------#
  # Export Functions #
  # ------------------#

  @doc """
    Exports the schema, including data types, objects, and classes.
  """
  @spec export_schema() :: %{
          base_event: map(),
          classes: map(),
          objects: map(),
          types: map(),
          version: binary()
        }
  def export_schema() do
    %{
      :base_event => Schema.export_base_event(),
      :classes => Schema.export_classes(),
      :objects => Schema.export_objects(),
      :types => Schema.export_data_types(),
      :version => Schema.version()
    }
  end

  @spec export_schema(Repo.extensions_t()) :: %{
          base_event: map(),
          classes: map(),
          objects: map(),
          types: map(),
          version: binary()
        }
  def export_schema(extensions) do
    %{
      :base_event => Schema.export_base_event(),
      :classes => Schema.export_classes(extensions),
      :objects => Schema.export_objects(extensions),
      :types => Schema.export_data_types(),
      :version => Schema.version()
    }
  end

  @spec export_schema(Repo.extensions_t(), Repo.profiles_t() | nil) :: %{
          base_event: map(),
          classes: map(),
          objects: map(),
          types: map(),
          version: binary()
        }
  def export_schema(extensions, nil) do
    export_schema(extensions)
  end

  def export_schema(extensions, profiles) do
    %{
      :base_event => Schema.export_base_event(profiles),
      :classes => Schema.export_classes(extensions, profiles),
      :objects => Schema.export_objects(extensions, profiles),
      :types => Schema.export_data_types(),
      :version => Schema.version()
    }
  end

  @doc """
    Exports the data types.
  """
  @spec export_data_types :: any
  def export_data_types() do
    Map.get(data_types(), :attributes)
  end

  @doc """
    Exports the classes.
  """
  @spec export_classes() :: map()
  def export_classes(), do: Repo.export_classes() |> reduce_objects()

  @spec export_classes(Repo.extensions_t()) :: map()
  def export_classes(extensions), do: Repo.export_classes(extensions) |> reduce_objects()

  @spec export_classes(Repo.extensions_t(), Repo.profiles_t() | nil) :: map()
  def export_classes(extensions, nil), do: export_classes(extensions)

  def export_classes(extensions, profiles) do
    Repo.export_classes(extensions) |> update_exported_classes(profiles)
  end

  @spec export_base_event() :: map()
  def export_base_event() do
    Repo.export_base_event()
    |> reduce_attributes()
    |> Map.update!(:attributes, fn attributes ->
      Utils.remove_profiles(attributes) |> Enum.into(%{})
    end)
  end

  @spec export_base_event(Repo.profiles_t() | nil) :: map()
  def export_base_event(nil) do
    export_base_event()
  end

  def export_base_event(profiles) do
    size = MapSet.size(profiles)

    Repo.export_base_event()
    |> reduce_attributes()
    |> Map.update!(:attributes, fn attributes ->
      Utils.apply_profiles(attributes, profiles, size) |> Enum.into(%{})
    end)
  end

  defp update_exported_classes(classes, profiles) do
    apply_profiles(classes, profiles, MapSet.size(profiles)) |> reduce_objects()
  end

  @doc """
    Exports the objects.
  """
  @spec export_objects() :: map()
  def export_objects(), do: Repo.export_objects() |> reduce_objects()

  @spec export_objects(Repo.extensions_t()) :: map()
  def export_objects(extensions), do: Repo.export_objects(extensions) |> reduce_objects()

  @spec export_objects(Repo.extensions_t(), Repo.profiles_t() | nil) :: map()
  def export_objects(extensions, nil), do: export_objects(extensions)

  def export_objects(extensions, profiles) do
    Repo.export_objects(extensions)
    |> apply_profiles(profiles, MapSet.size(profiles))
    |> reduce_objects()
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
  Returns a randomly generated sample event.
  """
  @spec generate_event(Cache.class_t() | atom() | binary()) :: nil | map()
  def generate_event(class) when is_map(class) do
    Schema.Generator.generate_sample_event(class, nil)
  end

  def generate_event(class) do
    Schema.class(class) |> Schema.Generator.generate_sample_event(nil)
  end

  @doc """
  Returns a randomly generated sample event, based on the spcified profiles.
  """
  @spec generate_event(Cache.class_t(), Repo.profiles_t() | nil) :: map()
  def generate_event(class, profiles) when is_map(class) do
    Schema.Generator.generate_sample_event(class, profiles)
  end

  @doc """
  Returns randomly generated sample object data.
  """
  @spec generate_object(Cache.object_t() | atom() | binary()) :: any()
  def generate_object(type) when is_map(type) do
    Schema.Generator.generate_sample_object(type, nil)
  end

  def generate_object(type) do
    Schema.object(type) |> Schema.Generator.generate_sample_object(nil)
  end

  @doc """
  Returns randomly generated sample object data, based on the spcified profiles.
  """
  @spec generate_object(Cache.object_t(), Repo.profiles_t() | nil) :: map()
  def generate_object(type, profiles) when is_map(type) do
    Schema.Generator.generate_sample_object(type, profiles)
  end

  defp get_category(id) do
    Repo.category(id) |> reduce_category()
  end

  defp get_category(extensions, id) do
    Repo.category(extensions, id) |> reduce_category()
  end

  defp reduce_category(nil) do
    nil
  end

  defp reduce_category(data) do
    Map.update(data, :classes, [], fn classes ->
      Enum.into(classes, %{}, fn {name, class} ->
        {name, reduce_class(class)}
      end)
    end)
  end

  defp reduce_objects(objects) do
    Enum.into(objects, %{}, fn {name, object} ->
      updated = reduce_attributes(object)

      {name, updated}
    end)
  end

  defp reduce_data(object) do
    delete_links(object) |> Map.delete(:_source)
  end

  defp reduce_attributes(data) do
    reduce_data(data)
    |> Map.update(:attributes, [], fn attributes ->
      Enum.into(attributes, %{}, fn {name, attribute} ->
        {name, reduce_data(attribute)}
      end)
    end)
  end

  @spec reduce_class(map) :: map
  def reduce_class(data) do
    delete_attributes(data) |> delete_associations()
  end

  @spec delete_attributes(map) :: map
  def delete_attributes(data) do
    Map.delete(data, :attributes)
  end

  @spec delete_associations(map) :: map
  def delete_associations(data) do
    Map.delete(data, :associations)
  end

  @spec delete_links(map) :: map
  def delete_links(data) do
    Map.delete(data, :_links)
  end

  def apply_profiles(types, _profiles, 0) do
    Enum.into(types, %{}, fn {name, type} ->
      remove_profiles(name, type)
    end)
  end

  def apply_profiles(types, profiles, size) do
    Enum.into(types, %{}, fn {name, type} ->
      apply_profiles(name, type, profiles, size)
    end)
  end

  defp apply_profiles(name, type, profiles, size) do
    {
      name,
      Map.update!(type, :attributes, fn attributes ->
        Utils.apply_profiles(attributes, profiles, size)
      end)
    }
  end

  defp remove_profiles(name, type) do
    {
      name,
      Map.update!(type, :attributes, fn attributes ->
        Utils.remove_profiles(attributes)
      end)
    }
  end
end
