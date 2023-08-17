# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Reader do
  @moduledoc """
  This module contains functions to read, parse, and merge json files.
  """
  require Logger

  alias Schema.Maps

  # The schema uses JSON files
  @schema_file ".json"

  # The Schema version file
  @version_file "version.json"

  # The Schema extension file
  @extension_file "extension.json"

  # The include directive
  @include :"$include"

  # Annotations are added to all attributes
  @annotations :annotations

  # The schema attribute names
  @attributes :attributes

  @doc """
  Reads and parses all JSON files in the given `path`.

  Returns a map with the contents of the files found in the `path`, or raises a
  `File.Error` or `Jason.DecodeError` exception if an error occurs.
  """
  @spec read_dir!(Path.t(), Path.t()) :: map
  def read_dir!(home, path),
    do: read_dir!([], home, path)

  defp read_dir!(acc, home, path) do
    if File.dir?(path) do
      Logger.info("[] read_dir: #{path}")

      File.ls!(path)
      |> Stream.map(fn file -> Path.join(path, file) end)
      |> Enum.reduce(acc, fn file, map -> read_dir!(map, home, file) end)
    else
      if Path.extname(path) == @schema_file do
        data = read!(path) |> resolve_included_files(home)
        [data | acc]
      else
        acc
      end
    end
  end

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

  @doc """
  Resolves extends files into the given data.

  Returns a new map, updated with attributes and properties from the
  included files.
  """
  def resolve_extends(items) do
    Enum.map(items, fn {name, item} ->
      {name, resolve_extends(items, item)}
    end)
  end

  @doc """
  Reads and parses extension's version files in the given `path` or `list` of paths.

  Returns a list with the contents of the files found in the `path`, or raises a
  `File.Error` or `Jason.DecodeError` exception if an error occurs.
  """
  @spec read_extensions(binary, binary | maybe_improper_list) :: any
  def read_extensions(home, path) when is_binary(path) do
    extensions(home, path, [])
  end

  def read_extensions(home, list) when is_list(list) do
    Enum.reduce(list, [], fn path, acc ->
      extensions(home, String.trim(path), acc)
    end)
    |> Enum.uniq_by(fn ext -> ext[:path] end)
  end

  @doc """
  Reads the schema version file in the given `path`.

  Returns a map with the contents of the file found in the `path`, or raises a
  `File.Error` or `Jason.DecodeError` exception if an error occurs.
  """
  @spec read_version(Path.t()) :: map()
  def read_version(path) do
    Path.join(path, @version_file) |> read!()
  end

  defp extensions(home, path, list) do
    Logger.info("extensions: #{path}")
    if File.dir?(path) do
      path
    else
      Path.join(home, path) |> Path.absname()
    end
    |> Path.expand()
    |> extensions(list)
  end

  defp extensions(path, list) do
    if File.dir?(path) do
      case extension(path) do
        false ->
          case File.ls(path) do
            {:ok, files} ->
              files
              |> Enum.map(fn file -> Path.join(path, file) end)
              |> Enum.reduce(list, fn file, acc -> extensions(file, acc) end)

            error ->
              Logger.error("unable to access #{path} directory. Error: #{inspect(error)}")
              list
          end

        data ->
          [Map.put(data, :path, path) | list]
      end
    else
      if !File.regular?(path) do
        # invalid directory name
        Logger.warning("invalid extensions path: #{path}")
      end
      list
    end
  end

  defp extension(path) do
    file = Path.join(path, @version_file)

    if File.regular?(file) do
      read!(file)
    else
      file = Path.join(path, @extension_file)

      if File.regular?(file) do
        read!(file)
      else
        false
      end
    end
  end

  defp resolve_extends(items, item) do
    case item[:extends] do
      nil ->
        item

      extends ->
        Logger.info("resolve_extends: #{item[:name]} extends #{extends}")

        case find_super_class(items, item, extends) do
          nil ->
            Logger.error("Error: #{item[:name]} extends undefined item: #{extends}")
            item

          base ->
            base = resolve_extends(items, base)

            attributes =
              Maps.deep_merge(base[:attributes], item[:attributes])
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
            case Map.get(classes, Schema.Utils.to_uid(extension, extends)) do
              nil -> Map.get(classes, String.to_atom(extends))
              other -> other
            end
        end

      base ->
        base
    end
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
        Logger.warning("ETS table with name #{name} already exists.")
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
