defmodule Schema.Profiles do
  @moduledoc """
  Profiles helper functions
  """

  require Logger

  @doc """
    Returns a new, empty profile.
  """
  def new(), do: MapSet.new()

  @doc """
    Creates a new  profile.
  """
  def new(profiles) when is_list(profiles) do
    MapSet.new(profiles)
  end

  def new(nil) do
    MapSet.new()
  end

  def new(%MapSet{} = profiles) do
    profiles
  end

  @doc """
    Filter attributes based on a given set of profiles.
  """
  def apply_profiles(class, profiles) when is_list(profiles) do
    apply_profiles(class, MapSet.new(profiles))
  end

  def apply_profiles(class, %MapSet{} = profiles) do
    size = MapSet.size(profiles)

    Map.update!(class, :attributes, fn attributes ->
      apply_profiles(attributes, profiles, size)
    end)
    |> Map.update!(:objects, fn objects ->
      Enum.map(objects, fn {name, object} ->
        {name,
         Map.update!(object, :attributes, fn attributes ->
           apply_profiles(attributes, profiles, size)
         end)}
      end)
    end)
  end

  defp apply_profiles(attributes, _profiles, 0) do
    remove_profiles(attributes)
  end

  defp apply_profiles(attributes, profiles, _size) do
    Enum.filter(attributes, fn {_k, v} ->
      case v[:profile] do
        nil -> true
        profile -> MapSet.member?(profiles, profile)
      end
    end)
  end

  defp remove_profiles(attributes) do
    Enum.filter(attributes, fn {_k, v} -> Map.has_key?(v, :profile) == false end)
  end

  @doc """
    Checks classes or objects if all profile attributes are defined.
  """
  def sanity_check(maps, profiles) do
    Enum.each(maps, fn {name, map} ->
      sanity_check(name, map[:attributes], map[:profiles], profiles)
    end)

    maps
  end

  @doc """
    Checks if all profile attributes are defined in the given attribute set.
  """
  def sanity_check(_name, _attributes, nil, _all_profiles) do
  end

  def sanity_check(name, attributes, profiles, all_profiles) do
    Enum.map(profiles, fn p ->
      case all_profiles[p] do
        nil ->
          Logger.warn("#{name} uses undefined profile: #{p}")

        profile ->
          check_profile(name, profile, attributes)
      end
    end)
  end

  defp check_profile(name, profile, attributes) do
    Enum.each(profile[:attributes], fn {k, p} ->
      if Map.has_key?(attributes, k) == false do
        text = "#{name} uses '#{profile[:name]}' profile, but it does not define '#{k}' attribute"

        if p[:requirement] == "required" do
          Logger.warn(text)
        else
          Logger.info(text)
        end
      end
    end)
  end
end
