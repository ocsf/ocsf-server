# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Utils do
  @moduledoc """
  Defines map helper functions.
  """

  @type class_t() :: map()
  @type object_t() :: map()
  @type category_t() :: map()
  @type dictionary_t() :: map()

  @type link_t() :: %{
          :group => :common | :class | :object,
          :type => String.t(),
          :caption => String.t(),
          optional(:deprecated?) => boolean(),
          optional(:attribute_keys) => nil | Enumerable.t(String.t())
        }

  @type version_t() :: %{
          :major => integer(),
          :minor => integer(),
          :patch => integer(),
          optional(:prerelease) => nil | String.t()
        }
  @type version_error_t() :: {:error, String.t(), any()}
  @type version_or_error_t() :: version_t() | version_error_t()

  @type string_set_t() :: MapSet.t(String.t())

  require Logger

  @spec to_uid(String.t() | atom()) :: atom()
  def to_uid(name) when is_binary(name) do
    String.to_atom(name)
  end

  def to_uid(name) when is_atom(name) do
    name
  end

  @spec to_uid(nil | String.t() | atom(), String.t() | atom()) :: atom()
  def to_uid(nil, name) when is_binary(name) do
    String.to_atom(name)
  end

  def to_uid(nil, name) when is_atom(name) do
    name
  end

  def to_uid(extension, name) do
    String.to_atom("#{extension}/#{name}")
  end

  @doc """
  Makes a type uid for the given class and activity identifiers.
  """
  @spec type_uid(number(), number()) :: number()
  def type_uid(class_uid, activity_id) do
    class_uid * 100 + activity_id
  end

  @spec filter_items_by_extensions(map() | nil, string_set_t() | nil) :: map() | nil
  def filter_items_by_extensions(nil, _extensions) do
    nil
  end

  def filter_items_by_extensions(items, nil) do
    items
  end

  def filter_items_by_extensions(items, extensions) do
    Enum.filter(items, fn {_key, item} ->
      extension = item[:extension]
      extension == nil or MapSet.member?(extensions, extension)
    end)
    |> filter_items_links_by_extension(extensions)
  end

  @spec filter_items_links_by_extension([{atom(), map()}], string_set_t()) :: map()
  defp filter_items_links_by_extension(items, extensions) do
    Enum.into(items, %{}, fn {item_key, item} ->
      links = filter_links_by_extension(item[:_links], extensions)
      {item_key, Map.put(item, :_links, links)}
    end)
  end

  @spec filter_item_links_by_extensions(map() | nil, string_set_t() | nil) :: map() | nil
  def filter_item_links_by_extensions(nil, _extensions) do
    nil
  end

  def filter_item_links_by_extensions(item, nil) do
    item
  end

  def filter_item_links_by_extensions(item, extensions) do
    Map.update(item, :_links, [], fn links -> filter_links_by_extension(links, extensions) end)
  end

  @spec filter_links_by_extension(nil | [map()], string_set_t()) :: [map()]
  defp filter_links_by_extension(nil, _extensions) do
    []
  end

  defp filter_links_by_extension(links, nil) do
    links
  end

  defp filter_links_by_extension(links, extensions) do
    Enum.filter(links, fn link ->
      # link item is NOT from an extension OR is member of extensions set
      extension = link[:extension]
      extension == nil or MapSet.member?(extensions, link[:extension])
    end)
  end

  @spec filter_clean_items_by_extensions(map() | nil, string_set_t() | nil) :: map() | nil
  def filter_clean_items_by_extensions(nil, _extensions) do
    nil
  end

  def filter_clean_items_by_extensions(items, nil) do
    items
  end

  def filter_clean_items_by_extensions(items, extensions) do
    Enum.filter(items, fn {_key, item} ->
      extension = item[:extension]
      extension == nil or MapSet.member?(extensions, extension)
    end)
    |> Enum.into(%{})
  end

  @doc """
  Filter attributes in items based on the given profiles.
  """
  @spec filter_items_attributes_by_profiles(
          map() | list() | nil,
          nil | list(String.t()) | string_set_t()
        ) :: map() | nil
  def filter_items_attributes_by_profiles(nil, _profiles) do
    nil
  end

  def filter_items_attributes_by_profiles(items, nil) do
    items
  end

  def filter_items_attributes_by_profiles(items, profiles) do
    Enum.into(items, %{}, fn {item_name, item} ->
      {item_name, filter_item_attributes_by_profiles(item, profiles)}
    end)
  end

  @doc """
  Filter attributes in an item based on the given profiles.
  """
  @spec filter_item_attributes_by_profiles(
          map(),
          nil | list(String.t()) | string_set_t()
        ) :: map()
  def filter_item_attributes_by_profiles(item, profiles) do
    Map.update!(item, :attributes, fn attributes ->
      filter_attributes_by_profiles(attributes, profiles)
    end)
  end

  @doc """
  Filter attributes based on the given profiles.
  """
  @spec filter_attributes_by_profiles(
          Enum.t() | nil,
          nil | list(String.t()) | string_set_t()
        ) :: Enum.t() | nil
  def filter_attributes_by_profiles(nil, _profiles) do
    nil
  end

  def filter_attributes_by_profiles(attributes, nil) do
    attributes
  end

  def filter_attributes_by_profiles(attributes, profiles) when is_list(profiles) do
    profiles = MapSet.new(profiles)
    filter_attributes_by_profiles_set(attributes, profiles)
  end

  def filter_attributes_by_profiles(attributes, %MapSet{} = profiles) do
    filter_attributes_by_profiles_set(attributes, profiles)
  end

  def filter_attributes_by_profiles(attributes, _profiles) do
    attributes
  end

  @spec filter_attributes_by_profiles_set(Enum.t(), string_set_t()) :: Enum.t()
  defp filter_attributes_by_profiles_set(attributes, profiles) when is_map(attributes) do
    Map.filter(attributes, fn {_k, a} ->
      a[:profiles] == nil || Enum.any?(a[:profiles], fn ap -> MapSet.member?(profiles, ap) end)
    end)
  end

  defp filter_attributes_by_profiles_set(attributes, profiles) do
    Enum.filter(attributes, fn {_k, a} ->
      a[:profiles] == nil || Enum.any?(a[:profiles], fn ap -> MapSet.member?(profiles, ap) end)
    end)
  end

  @version_regex ~r/^(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)(?:-(?<prerelease>.+))?$/

  @spec version_regex_source() :: String.t()
  def version_regex_source(), do: @version_regex.source

  @spec parse_version(any()) :: version_or_error_t()
  def parse_version(s) when is_binary(s) do
    captured = Regex.named_captures(@version_regex, s)

    if captured do
      major = parse_integer(captured["major"])
      minor = parse_integer(captured["minor"])
      patch = parse_integer(captured["patch"])
      prerelease = captured["prerelease"]

      if major && minor && patch do
        if prerelease && prerelease != "" do
          %{major: major, minor: minor, patch: patch, prerelease: prerelease}
        else
          %{major: major, minor: minor, patch: patch}
        end
      else
        # This should never happen due to regex, but here to be defensive
        {:error, "non-integral", s}
      end
    else
      {:error, "malformed", s}
    end
  end

  def parse_version(v) do
    {:error, "not a string", v}
  end

  defp parse_integer(s) do
    case Integer.parse(s) do
      {number, ""} -> number
      _ -> nil
    end
  end

  @spec version_is_initial_development?(version_or_error_t()) :: boolean()
  def version_is_initial_development?(v) when is_map(v) do
    v[:major] == 0
  end

  def version_is_initial_development?(v) when is_tuple(v), do: false

  @spec version_is_prerelease?(version_or_error_t()) :: boolean()
  def version_is_prerelease?(v) when is_map(v) do
    prerelease = v[:prerelease]
    is_binary(prerelease) and prerelease != ""
  end

  def version_is_prerelease?(v) when is_tuple(v), do: false

  @spec version_sorter(version_or_error_t(), version_or_error_t()) :: boolean()
  def version_sorter(v1, v2) when is_map(v1) and is_map(v2) do
    cond do
      v1 == v2 ->
        true

      v1[:major] < v2[:major] ->
        true

      v1[:major] == v2[:major] and v1[:minor] < v2[:minor] ->
        true

      v1[:major] == v2[:major] and v1[:minor] == v2[:minor] and v1[:patch] < v2[:patch] ->
        true

      v1[:major] == v2[:major] and v1[:minor] == v2[:minor] and v1[:patch] == v2[:patch] ->
        cond do
          Map.has_key?(v1, :prerelease) and Map.has_key?(v2, :prerelease) ->
            v1[:prerelease] <= v2[:prerelease]

          Map.has_key?(v1, :prerelease) and not Map.has_key?(v2, :prerelease) ->
            true

          not Map.has_key?(v1, :prerelease) and Map.has_key?(v2, :prerelease) ->
            false

          # Covered by v1 == v2:
          #   not Map.has_key?(v1, :prerelease) and not Map.has_key?(v2, :prerelease)

          true ->
            true
        end

      true ->
        false
    end
  end

  def version_sorter(v1, v2) do
    case {v1, v2} do
      {{:error, _, original1}, {:error, _, original2}} ->
        original1 <= original2

      {{:error, _, _}, _} ->
        true

      {_, {:error, _, _}} ->
        false

      _ ->
        false
    end
  end

  @spec version_sorter_desc(version_or_error_t(), version_or_error_t()) :: boolean()
  def version_sorter_desc(v1, v2) do
    not version_sorter(v1, v2)
  end

  @spec clean_items(map()) :: map()
  def clean_items(items) do
    Enum.into(items, %{}, fn {item_name, item} ->
      {item_name, clean_item(item)}
    end)
  end

  @spec clean_item(map()) :: map()
  def clean_item(item) do
    clean_item = filter_internal(item)

    if Map.has_key?(clean_item, :attributes) do
      Map.update(clean_item, :attributes, [], fn attributes ->
        Enum.into(attributes, %{}, fn {attribute_name, attribute_details} ->
          {attribute_name, clean_attributes(attribute_details)}
        end)
      end)
    else
      clean_item
    end
  end

  @spec clean_attributes(map()) :: map()
  defp clean_attributes(attribute_details) do
    attribute_details
    |> filter_internal()
    |> clean_enum()
  end

  @spec clean_enum(map()) :: map()
  defp clean_enum(attribute_details) do
    if Map.has_key?(attribute_details, :enum) do
      Map.update!(attribute_details, :enum, fn enum ->
        Enum.map(
          enum,
          fn {enum_value_key, enum_value_details} ->
            {
              enum_value_key,
              filter_internal(enum_value_details)
            }
          end
        )
        |> Enum.into(%{})
      end)
    else
      attribute_details
    end
  end

  @spec filter_internal(map()) :: map()
  defp filter_internal(m) do
    Map.filter(m, fn {key, _} ->
      not String.starts_with?(to_string(key), "_")
    end)
  end

  @spec descope(atom() | String.t()) :: String.t()
  def descope(name) when is_binary(name) do
    Path.basename(name)
  end

  def descope(name) when is_atom(name) do
    Path.basename(Atom.to_string(name))
  end

  @spec descope_to_uid(atom() | String.t()) :: atom()
  def descope_to_uid(name) when is_binary(name) do
    String.to_atom(Path.basename(name))
  end

  def descope_to_uid(name) when is_atom(name) do
    String.to_atom(Path.basename(Atom.to_string(name)))
  end

  @spec observable_type_id_to_atom(any()) :: atom()
  def observable_type_id_to_atom(observable_type_id) when is_integer(observable_type_id) do
    Integer.to_string(observable_type_id) |> String.to_atom()
  end

  def observable_type_id_to_atom(observable_type_id) do
    Logger.error(
      "Bad observable type_id - cannot convert non-integer to atom: #{inspect(observable_type_id)}"
    )

    System.stop(1)
    -1
  end

  @spec find_parent(map(), String.t()) :: {atom() | nil, map() | nil}
  def find_parent(items, extends) do
    if extends do
      extends_key = String.to_atom(extends)
      parent_item = Map.get(items, extends_key)

      if parent_item do
        {extends_key, parent_item}
      else
        {extends_key, nil}
      end
    else
      {nil, nil}
    end
  end
end
