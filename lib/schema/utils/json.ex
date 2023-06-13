# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Utils.JSON do
  @moduledoc """
  This module contains functions to read, parse, and merge json files.
  """
  require Logger

  alias Schema.Utils.Maps

  # The schema uses JSON files
  @schema_file ".json"

  # The include directive
  @include :"$include"

  # Annotations are added to all attributes
  @annotations :annotations

  # The schema attribute names
  @attributes :attributes

  @doc """
  Reads and parses a JSON file.

  Returns a map with the contents of the given filename, or raises a
  `File.Error` or `Jason.DecodeError` exception if an error occurs.
  """
  @spec read!(Path.t()) :: map
  def read!(path) do
    Logger.info("read file: #{path}")

    path
    |> File.read!()
    |> Jason.decode!(keys: :atoms)
    |> Map.pop(@annotations)
    |> apply_annotations()
  end

  @doc """
  Reads and parses all JSON files in the given `path`.

  Returns a map with the contents of the files found in the `path`, or raises a
  `File.Error` or `Jason.DecodeError` exception if an error occurs.
  """
  @spec read_dir!(Path.t(), Path.t()) :: map
  def read_dir!(home, path),
    do: read_dir!(%{}, home, path)

  defp read_dir!(acc, home, path) do
    if File.dir?(path) do
      Logger.info("[] read_dir: #{path}")

      File.ls!(path)
      |> Stream.map(fn file -> Path.join(path, file) end)
      |> Enum.reduce(acc, fn file, map -> read_dir!(map, home, file) end)
    else
      if Path.extname(path) == @schema_file do
        data = read!(path) |> resolve_included_files(home)
        Map.put(acc, String.to_atom(data[:name]), data)
      else
        acc
      end
    end
  end

  @doc """
  Resolves, reads, and merges the included files into the given data.

  Returns a new map, updated with attributes and properties from the
  included files.
  """
  @spec resolve_included_files(map, Path.t()) :: map
  def resolve_included_files(data, home) do
    read_included_files(data, fn path ->
      {nil, Path.join(home, path)}
    end)
  end

  defp apply_annotations({nil, data}),
    do: data

  defp apply_annotations({annotations, data}) do
    Logger.info("#{data[:caption]} apply_annotations: #{inspect(annotations)}")
    Maps.put_new_in(data, @attributes, annotations)
  end

  defp read_included_files(data, resolver) do
    include_files(
      fn file, data ->
        included = read_file(resolver, file)

        Map.update!(data, @attributes, fn attributes ->
          Maps.deep_merge(Map.get(included, @attributes), attributes)
        end)
      end,
      pop_in(data, [@attributes, @include])
    )
    |> include(resolver)
  end

  defp include(data, resolver) do
    Map.update!(data, @attributes, fn attributes -> merge_attributes(resolver, attributes) end)
  end

  defp include_files(_resolver, {nil, data}),
    do: data

  defp include_files(resolver, {file, data}) when is_binary(file),
    do: resolver.(file, data)

  defp include_files(resolver, {files, data}) when is_list(files),
    do: Enum.reduce(files, data, fn file, acc -> resolver.(file, acc) end)

  defp merge_attributes(resolver, attributes) do
    Enum.into(
      attributes,
      Map.new(),
      fn {name, map} ->
        {
          name,
          include_files(
            fn file, data ->
              Maps.deep_merge(data, read_file(resolver, file))
            end,
            Map.pop(map, @include)
          )
        }
      end
    )
  end

  defp read_file(resolver, file) do
    {ext, path} = resolver.(file)

    case cache_get(path) do
      [] ->
        Logger.info("[#{ext}] read_file #{path}")
        read!(path) |> cache_put(path)

      [{_, cached}] ->
        Logger.info("[#{ext}] read_file[cached] #{path}")
        cached
    end
  end

  # ETS cache for the included json files
  def cache_init() do
    name = __MODULE__

    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:set, :protected, :named_table])
        :ok

      _ ->
        Logger.warn("ETS table with name #{name} already exists.")
        cache_clear()
        :ok
    end
  end

  def cache_clear() do
    :ets.delete_all_objects(__MODULE__)
  end

  defp cache_put(data, path) do
    :ets.insert(__MODULE__, {path, data})
    data
  end

  defp cache_get(path) do
    :ets.lookup(__MODULE__, path)
  end
end
