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
    Map.update(Repo.categories(extensions), :attributes, Map.new(), fn attributes ->
      Enum.map(attributes, fn {name, _category} ->
        {name, category(extensions, name)}
      end)
      # |> Enum.filter(fn {_name, category} -> map_size(category[:classes]) > 0 end)
      |> Map.new()
    end)
  end

  @doc """
    Returns a single category with its classes.
  """
  @spec category(atom | String.t()) :: nil | Cache.category_t()
  def category(id), do: get_category(Utils.to_uid(id))

  @spec category(Repo.extensions(), String.t()) :: nil | Cache.category_t()
  def category(extensions, id), do: get_category(extensions, Utils.to_uid(id))

  @spec category(Repo.extensions(), String.t(), String.t()) :: nil | Cache.category_t()
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
  @spec dictionary(Repo.extensions()) :: Cache.dictionary_t()
  def dictionary(extensions), do: Repo.dictionary(extensions)

  @doc """
    Returns the data types defined in dictionary.
  """
  @spec data_types :: map()
  def data_types(), do: Repo.data_types()

  @doc """
    Returns all event classes.
  """
  @spec classes() :: map()
  def classes(), do: Repo.classes()

  @spec classes(Repo.extensions()) :: map()
  def classes(extensions), do: Repo.classes(extensions)

  @doc """
    Returns a single event class.
  """
  @spec class(atom() | String.t()) :: nil | Cache.class_t()
  def class(id), do: Repo.class(Utils.to_uid(id))

  @spec class(nil | String.t(), String.t()) :: nil | map()
  def class(extension, id) when is_binary(id),
    do: Repo.class(Utils.to_uid(extension, id))

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

  @spec objects(Repo.extensions()) :: map()
  def objects(extensions), do: Repo.objects(extensions)

  @doc """
    Returns a single objects.
  """
  @spec object(atom | String.t()) :: nil | Cache.object_t()
  def object(id), do: Repo.object(Utils.to_uid(id))

  @spec object(nil | String.t(), String.t()) :: nil | map()
  def object(extension, id) when is_binary(id) do
    Repo.object(Utils.to_uid(extension, id))
  end

  @spec object(Repo.extensions(), String.t(), String.t()) :: nil | map()
  def object(extensions, extension, id) when is_binary(id) do
    Repo.object(extensions, Utils.to_uid(extension, id))
  end


  #------------------#
  # Export Functions #
  #------------------#
  
  @doc """
    Exports the schema, including data types, objects, abd classes.
  """
  @spec export_schema() :: %{classes: map(), objects: map(), types: map(), version: binary()}
  def export_schema() do
    %{
      :classes => Schema.export_classes(),
      :objects => Schema.export_objects(),
      :types => Schema.export_data_types(),
      :version => Schema.version()
    }
  end

  @spec export_schema(MapSet.t(binary)) :: %{classes: map(), objects: map(), types: map(), version: binary()}
  def export_schema(extensions) do
    %{
      :classes => Schema.export_classes(extensions),
      :objects => Schema.export_objects(extensions),
      :types => Schema.export_data_types(),
      :version => Schema.version()
    }
  end

  @spec export_schema(MapSet.t(binary), list(binary) | nil) :: %{classes: map(), objects: map(), types: map(), version: binary()}
  def export_schema(extensions, _profiles) do
    %{
      :classes => Schema.export_classes(extensions),
      :objects => Schema.export_objects(extensions),
      :types => Schema.export_data_types(),
      :version => Schema.version()
    }
  end

  @doc """
    Exports a single category and its classes.
  """
  @spec export_category(atom | String.t()) :: nil | Cache.category_t()
  def export_category(id), do: export_category_classes(Utils.to_uid(id))

  @spec export_category(Repo.extensions(), String.t()) :: nil | Cache.category_t()
  def export_category(extensions, id), do: export_category_classes(extensions, Utils.to_uid(id))

  @spec export_category(Repo.extensions(), String.t(), String.t()) :: nil | Cache.category_t()
  def export_category(extensions, extension, id),
    do: export_category_classes(extensions, Utils.to_uid(extension, id))

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

  @spec export_classes(Repo.extensions()) :: map()
  def export_classes(extensions), do: Repo.export_classes(extensions) |> reduce_objects()

  @doc """
    Exports the objects.
  """
  @spec export_objects() :: map()
  def export_objects(), do: Repo.export_objects() |> reduce_objects()

  @spec export_objects(Repo.extensions()) :: map()
  def export_objects(extensions), do: Repo.export_objects(extensions) |> reduce_objects()


  #------------------#
  # Sample Functions #
  #------------------#
  
  @doc """
  Returns a randomly generated sample event.
  """
  @spec event(atom() | map()) :: nil | map()
  def event(class) when is_atom(class) do
    Schema.class(class) |> Schema.Generator.event()
  end

  def event(class) when is_map(class) do
    Schema.Generator.event(class)
  end

  @doc """
  Returns a randomly generated sample event.
  """
  @spec generate_event(Cache.class_t(), list() | nil) :: map()
  def generate_event(class, nil) when is_map(class) do
    Schema.Generator.event(class)
    |> Map.delete(:profiles)
  end

  def generate_event(class, []) do
    Map.update!(class, :attributes, fn attributes ->
      Utils.apply_profiles(attributes, [])
    end)
    |> Schema.Generator.event()
    |> Map.put(:profiles, [])
  end

  def generate_event(class, profiles) do
    Map.update!(class, :attributes, fn attributes ->
      Utils.apply_profiles(attributes, profiles)
    end)
    |> Schema.Generator.event()
    |> Map.put(:profiles, profiles)
  end

  @doc """
  Returns randomly generated sample data.
  """
  @spec generate(map()) :: any()
  def generate(type) when is_map(type) do
    Schema.Generator.generate(type)
  end

  defp get_category(id) do
    Repo.category(id) |> reduce_category()
  end

  defp get_category(extensions, id) do
    Repo.category(extensions, id) |> reduce_category()
  end

  defp export_category_classes(id) do
    Repo.export_category(id) |> export_cat_classes()
  end

  defp export_category_classes(extensions, id) do
    Repo.export_category(extensions, id) |> export_cat_classes()
  end

  defp export_cat_classes(nil) do
    nil
  end

  defp export_cat_classes(category) do
    Map.update(category, :classes, Map.new(), fn classes -> reduce_objects(classes) end)
  end

  defp reduce_category(nil) do
    nil
  end

  defp reduce_category(data) do
    Map.update(data, :classes, [], fn classes ->
      Enum.map(classes, fn {name, class} ->
        {name, reduce_class(class)}
      end)
      |> Map.new()
    end)
  end

  defp reduce_objects(objects) do
    Enum.map(objects, fn {name, object} ->
      updated =
        reduce_object(object)
        |> reduce_attributes(&reduce_object/1)
        |> delete_see_also()

      {name, updated}
    end)
    |> Map.new()
  end

  defp reduce_object(object) do
    delete_links(object) |> Map.delete(:description)
  end

  defp reduce_attributes(data, reducer) do
    Map.update(data, :attributes, [], fn attributes ->
      Enum.map(attributes, fn {name, attribute} ->
        {name, reducer.(attribute)}
      end)
      |> Map.new()
    end)
  end

  @spec reduce_class(map) :: map
  def reduce_class(data) do
    delete_attributes(data) |> delete_see_also() |> delete_associations()
  end

  @spec delete_attributes(map) :: map
  def delete_attributes(data) do
    Map.delete(data, :attributes)
  end

  @spec delete_associations(map) :: map
  def delete_associations(data) do
    Map.delete(data, :associations)
  end

  @spec delete_see_also(map) :: map
  def delete_see_also(data) do
    Map.delete(data, :see_also)
  end

  @spec delete_links(map) :: map
  def delete_links(data) do
    Map.delete(data, :_links)
  end
end
