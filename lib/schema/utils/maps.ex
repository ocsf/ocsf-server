defmodule Schema.Utils.Maps do
  @moduledoc """
  This module contains helper functions to work with maps.
  """

  @doc """
  Merges two maps into one, resolving conflicts in favor of `map1` (i.e. the
  entries in `map1` "have precedence" over the entries in `map2`).
  """
  @spec merge_new(map, map | nil) :: map
  def merge_new(map1, nil), do: map1

  def merge_new(map1, map2) do
    Map.merge(map1, map2, fn _key, v1, _v2 -> v1 end)
  end

  @doc """
  Puts the `src` entries in all `maps` entries unless the `src` entry key
  already exists in the `maps` entry (i.e. the entries in `maps` "have precedence"
  over the entries in `src`).
  """
  @spec put_new(map, map | nil) :: map
  def put_new(maps, nil), do: maps

  def put_new(maps, src) do
    Enum.into(maps, %{}, fn
      {key, dst} when is_map(dst) ->
        {key, merge_new(dst, src)}

      {key, dst} ->
        {key, dst}
    end)
  end

  @doc """
  Puts the `src` entries in a nested maps. The entries in `maps` "have precedence"
  over the entries in `src`).
  """
  @spec put_new_in(map, atom | binary, map | nil) :: map
  def put_new_in(map, _key, nil), do: map

  def put_new_in(map, key, src) do
    Map.update!(map, key, fn maps ->
      put_new(maps, src)
    end)
  end

  @doc """
  Recursively merges two maps into one.

  The `map2` entries will be added to `map1` entries, overriding the existing
  entries. That is, the entries in `map2` "have precedence" over the entries
  in `map1`.
  """
  @spec deep_merge(map, map | nil) :: map
  def deep_merge(map, nil), do: map

  def deep_merge(map, src) do
    Map.merge(map, src, &deep_resolve/3)
  end

  # Key exists in both and both values are maps as well, then they can be merged recursively
  defp deep_resolve(_key, map1, map2) when is_map(map1) and is_map(map2) do
    if map_size(map1) == 0 do
      map2
    else
      if map_size(map2) == 0 do
        map1
      else
        deep_merge(map1, map2)
      end
    end
  end

  # Key exists in both maps, but at least one of the values is
  # NOT a map. We fall back to standard merge behavior, preferring
  # the value on the map2.
  defp deep_resolve(_key, _val1, val2) do
    val2
  end
end
