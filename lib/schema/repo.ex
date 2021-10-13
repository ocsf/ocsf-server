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
defmodule Schema.Repo do
  @moduledoc """
  This module keeps a cache of the schema files.
  """
  use Agent

  alias Schema.Cache

  @typedoc """
  Defines a set of extensions.
  """
  @type extensions() :: MapSet.t(binary())

  @spec start :: {:error, any} | {:ok, pid}
  def start(), do: Agent.start(fn -> Cache.init() end, name: __MODULE__)

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_), do: Agent.start_link(fn -> Cache.init() end, name: __MODULE__)

  @spec version :: String.t()
  def version(), do: Agent.get(__MODULE__, fn schema -> Cache.version(schema) end)

  @spec categories :: map()
  def categories() do
    Agent.get(__MODULE__, fn schema -> Cache.categories(schema) end)
  end

  @spec categories(extensions() | nil) :: map()
  def categories(nil) do
    Agent.get(__MODULE__, fn schema -> Cache.categories(schema) end)
  end

  def categories(extensions) do
    Agent.get(__MODULE__, fn schema ->
      Cache.categories(schema)
      |> Map.update!(:attributes, fn attributes ->
        filter(attributes, extensions)
      end)
    end)
  end

  @spec category(atom) :: nil | Cache.category_t()
  def category(id) do
    Agent.get(__MODULE__, fn schema -> Cache.categories(schema, id) end)
  end

  @spec category(extensions() | nil, atom) :: nil | Cache.category_t()
  def category(nil, id) do
    Agent.get(__MODULE__, fn schema -> Cache.categories(schema, id) end)
  end

  def category(extensions, id) do
    Agent.get(__MODULE__, fn schema ->
      Cache.categories(schema, id)
      |> Map.update!(:classes, fn class ->
        filter(class, extensions)
      end)
    end)
  end

  @spec dictionary() :: Cache.dictionary_t()
  def dictionary() do
    Agent.get(__MODULE__, fn schema -> Cache.dictionary(schema) end)
  end

  @spec dictionary(extensions() | nil) :: Cache.dictionary_t()
  def dictionary(nil) do
    Agent.get(__MODULE__, fn schema -> Cache.dictionary(schema) end)
  end

  def dictionary(extensions) do
    Agent.get(__MODULE__, fn schema ->
      Cache.dictionary(schema)
      |> Map.update!(:attributes, fn attributes ->
        filter(attributes, extensions)
      end)
    end)
  end

  @spec classes() :: map()
  def classes() do
    Agent.get(__MODULE__, fn schema -> Cache.classes(schema) end)
  end

  @spec classes(extensions() | nil) :: map()
  def classes(nil) do
    Agent.get(__MODULE__, fn schema -> Cache.classes(schema) end)
  end

  def classes(extensions) do
    Agent.get(__MODULE__, fn schema ->
      Cache.classes(schema) |> filter(extensions)
    end)
  end

  @spec class(atom) :: nil | Cache.class_t()
  def class(id) do
    Agent.get(__MODULE__, fn schema -> Cache.classes(schema, id) end)
  end

  def find_class(uid) do
    Agent.get(__MODULE__, fn schema -> Cache.find_class(schema, uid) end)
  end

  @spec objects() :: map()
  def objects() do
    Agent.get(__MODULE__, fn schema -> Cache.objects(schema) end)
  end

  @spec objects(extensions() | nil) :: map()
  def objects(nil) do
    Agent.get(__MODULE__, fn schema -> Cache.objects(schema) end)
  end

  def objects(extensions) do
    Agent.get(__MODULE__, fn schema ->
      Cache.objects(schema) |> filter(extensions)
    end)
  end

  @spec object(atom) :: nil | Cache.class_t()
  def object(nil), do: nil

  def object(id) do
    Agent.get(__MODULE__, fn schema -> Cache.objects(schema, id) end)
  end

  @spec reload() :: :ok
  def reload() do
    Schema.JsonReader.set_extension()
    Agent.cast(__MODULE__, fn _ -> Cache.init() end)
  end

  @spec reload(String.t() | list()) :: :ok
  def reload(extension) do
    Schema.JsonReader.set_extension(extension)
    Agent.cast(__MODULE__, fn _ -> Cache.init() end)
  end

  defp filter(objects, extensions) do
    Enum.filter(objects, fn {_k, f} ->
      extension = f[:extension]
      extension == nil or MapSet.member?(extensions, extension)
    end)
    |> Map.new()
  end
end
