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
defmodule Schema do
  @moduledoc """
  Schema keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """
  alias Schema.Repo
  alias Schema.Cache

  @doc """
    Returns the schema version string.
  """
  @spec version :: String.t()
  def version(), do: Repo.version()

  @doc """
    Returns the event categories.
  """
  @spec categories :: map()
  def categories(), do: Repo.categories()

  @spec categories(atom | String.t()) :: nil | Cache.category_t()
  def categories(id) when is_binary(id), do: Repo.categories(to_uid(id))
  def categories(id) when is_atom(id), do: Repo.categories(id)

  @spec categories(String.t() | nil, atom | String.t()) :: nil | Cache.category_t()
  def categories(nil, id) when is_binary(id), do: Repo.categories(to_uid(id))
  def categories(_extension, id) when is_binary(id), do: Repo.categories(to_uid(id))

  @doc """
    Returns the attribute dictionary.
  """
  @spec dictionary :: Cache.dictionary_t()
  def dictionary(), do: Repo.dictionary()

  @doc """
    Returns all event classes.
  """
  @spec classes() :: map()
  def classes(), do: Repo.classes()

  @doc """
    Returns a single event class.
  """
  @spec classes(atom | String.t()) :: nil | Cache.class_t()
  def classes(id) when is_binary(id), do: Repo.classes(to_uid(id))
  def classes(id) when is_atom(id), do: Repo.classes(id)

  @spec classes(nil | String.t(), String.t()) :: nil | map()
  def classes(nil, id) when is_binary(id), do: Repo.classes(to_uid(id))
  def classes(_extension,  id) when is_binary(id), do: Repo.classes(to_uid(id))

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

  @doc """
    Returns a single objects.
  """
  @spec objects(atom | String.t()) :: nil | Cache.object_t()
  def objects(id) when is_binary(id), do: Repo.objects(to_uid(id))
  def objects(id) when is_atom(id), do: Repo.objects(id)

  @spec objects(nil | String.t(), String.t()) :: nil | map()
  def objects(nil, id) when is_binary(id), do: Repo.objects(to_uid(id))
  def objects(_extension, id) when is_binary(id), do: Repo.objects(to_uid(id))

  @doc """
  Returns a randomly generated sample event.
  """
  @spec event(atom() | map()) :: nil | map()
  def event(class) when is_atom(class) do
    Schema.classes(class) |> Schema.Generator.event()
  end

  def event(class) when is_map(class) do
    Schema.Generator.event(class)
  end

  @doc """
  Returns a randomly generated sample data.
  """
  @spec generate(map()) :: any()
  def generate(type) when is_map(type) do
    Schema.Generator.generate(type)
  end
  def remove_links(data) do
    Map.delete(data, :_links) |> remove_links(:attributes)
  end
  def remove_links(data, key) do
    case data[key] do
      nil ->
        data

      attributes ->
        updated = Enum.map(attributes, fn {k, v} -> %{k => Map.delete(v, :_links)} end)
        Map.put(data, key, updated)
    end
  end

  @spec schema_map :: %{:children => list, :value => non_neg_integer, optional(any) => any}
  def schema_map() do
    base = get_class(:base_event)

    categories =
      Stream.map(
        Map.get(Schema.categories(), :attributes),
        fn {name, _} ->
          {classes, cat} = Schema.categories(name) |> Map.pop(:classes)

          children =
            Enum.map(
              classes,
              fn {name, _class} ->
                class = get_class(name)
                Map.put(Map.delete(class, :attributes), :value, length(class[:attributes]))
              end
            )
            |> Enum.sort(fn map1, map2 -> map1[:name] <= map2[:name] end)

          Map.put(cat, :type, name)
          |> Map.put(:children, children)
          |> Map.put(:value, length(children))
        end
      )
      |> Enum.to_list()
      |> Enum.sort(fn map1, map2 -> map1[:name] <= map2[:name] end)

    base
    |> Map.delete(:attributes)
    |> Map.put(:children, categories)
    |> Map.put(:value, length(categories))
  end

  defp get_class(name) do
    Schema.classes(name)
    |> Schema.remove_links()
    |> Map.delete(:see_also)
  end

  defp to_uid(name) do
     String.downcase(name) |> Cache.to_uid()
  end
end
