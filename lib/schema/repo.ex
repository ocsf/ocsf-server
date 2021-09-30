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

  @spec start :: {:error, any} | {:ok, pid}
  def start(), do: Agent.start(fn -> Cache.init() end, name: __MODULE__)

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_), do: Agent.start_link(fn -> Cache.init() end, name: __MODULE__)

  @spec version :: String.t()
  def version(), do: Agent.get(__MODULE__, fn schema -> Cache.version(schema) end)

  @spec categories :: map()
  def categories(), do: Agent.get(__MODULE__, fn schema -> Cache.categories(schema) end)

  @spec categories(atom) :: nil | Cache.category_t()
  def categories(id) do
    Agent.get(__MODULE__, fn schema -> Cache.categories(schema, id) end)
  end

  @spec dictionary :: Cache.dictionary_t()
  def dictionary(), do: Agent.get(__MODULE__, fn schema -> Cache.dictionary(schema) end)

  @spec classes() :: list()
  def classes(), do: Agent.get(__MODULE__, fn schema -> Cache.classes(schema) end)

  @spec classes(atom) :: nil | Cache.class_t()
  def classes(id) do
    Agent.get(__MODULE__, fn schema -> Cache.classes(schema, id) end)
  end

  def find_class(uid) do
    Agent.get(__MODULE__, fn schema -> Cache.find_class(schema, uid) end)
  end

  @spec objects() :: map()
  def objects(), do: Agent.get(__MODULE__, fn schema -> Cache.objects(schema) end)

  @spec objects(atom) :: nil | Cache.class_t()
  def objects(id) do
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
end
