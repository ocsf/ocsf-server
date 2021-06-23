defmodule Schema.CheckEnums do
  def classes() do
    Enum.each(Schema.classes(), fn {name, _class} ->
      each(Schema.classes(name)) |> print(name)
    end)
  end

  def objects() do
    Enum.each(Schema.objects(), fn {name, obj} ->
      each(obj) |> print(name)
    end)
  end

  defp print([], _name) do
    :ok
  end

  defp print(list, name) do
    text = Enum.join(list, ", ")
    IO.puts(name)
    IO.puts("   #{text}")
  end

  defp each(map) do
    Map.get(map, :attributes)
    |> Map.new()
    |> check()
  end

  defp check(attributes) do
    Enum.reduce(attributes, [], fn {name, attribute}, acc ->
      if is_enum?(attribute) do
        check_enum(attributes, name, Map.get(attribute, :enum), acc)
      else
        acc
      end
    end)
  end

  defp is_enum?(attribute) do
    Map.has_key?(attribute, :enum) and Map.get(attribute, :requirement) != "reserved"
  end

  defp check_enum(attributes, name, enum, acc) do
    name = Atom.to_string(name)

    key = get_base_name(name) |> String.to_atom()

    if Map.has_key?(attributes, key) do
      acc
    else
      if Map.has_key?(enum, :"-1") do
        ["#{name}*" | acc]
      else
        [name | acc]
      end
    end
  end

  defp get_base_name(name) do
    if String.ends_with?(name, "_id") do
      Path.basename(name, "_id")
    else
      Path.basename(name, "_ids")
    end
  end
end
