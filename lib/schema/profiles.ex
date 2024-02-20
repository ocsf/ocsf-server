defmodule Schema.Profiles do
  @moduledoc """
  Profiles helper functions
  """

  require Logger

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
  def sanity_check(group, maps, profiles) do
    profiles =
      Enum.reduce(maps, profiles, fn {name, map}, acc ->
        check_profiles(group, name, map, map[:profiles], acc)
      end)

    {maps, profiles}
  end

  # Checks if all profile attributes are defined in the given attribute set.
  defp check_profiles(_group, _name, _map, nil, all_profiles) do
    all_profiles
  end

  defp check_profiles(group, name, map, profiles, all_profiles) do
    Enum.reduce(profiles, all_profiles, fn p, acc ->
      case acc[p] do
        nil ->
          Logger.warning("#{name} uses undefined profile: #{p}")
          acc

        profile ->
          check_profile(name, profile, map[:attributes])
          link = %{group: group, type: Atom.to_string(name), caption: map[:caption]}
          profile = Map.update(profile, :_links, [link], fn links -> [link | links] end)
          Map.put(acc, p, profile)
      end
    end)
  end

  defp check_profile(name, profile, attributes) do
    Enum.each(profile[:attributes], fn {k, p} ->
      if Map.has_key?(attributes, k) == false do
        text = "#{name} uses '#{profile[:name]}' profile, but it does not define '#{k}' attribute"

        if p[:requirement] == "required" do
          Logger.warning(text)
        else
          Logger.info(text)
        end
      end
    end)
  end
end
