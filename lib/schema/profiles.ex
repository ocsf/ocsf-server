defmodule Schema.Profiles do
  @doc """
    Filter attributes based on a fiven set of profiles.
  """
  def apply_profiles(class, profiles) when is_list(profiles) do
    apply_profiles(class, MapSet.new(profiles))
  end

  def apply_profiles(class,  %MapSet{} = profiles) do
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
end
