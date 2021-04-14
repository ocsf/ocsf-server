defmodule Schema.Inspector do
  @moduledoc """
  SES Event data inspector.
  """

  require Logger

  @class_id "class_id"

  @string_types [
    "string_t",
    "ip_t",
    "path_t",
    "hostname_t",
    "email_t",
    "mac_t",
    "ipv4_t",
    "ipv6_t",
    "netmask_t",
    "json_t"
  ]

  @integer_types ["integer_t", "port_t", "timestamp_t", "long_t", "json_t"]
  @float_types ["float_t", "json_t"]
  @boolean_types ["boolean_t", "json_t"]

  @doc """
  Validates the given event using `class_id` value and the schema.
  """
  def validate(data) when is_map(data), do: data[@class_id] |> validate(data)

  def validate(_data), do: %{:error => "Not a JSON object"}

  defp validate(nil, _data), do: %{:error => "Missing class_id"}

  defp validate(class_id, data), do: validate_type(Schema.find_class(class_id), data)

  defp validate_type(nil, data) do
    class_id = data[@class_id]
    %{:error => "Unknown class_id: #{class_id}", :value => class_id}
  end

  defp validate_type(type, data) do
    Logger.info("validate: #{type.name}")

    Enum.reduce(type.attributes, %{}, fn {name, attribute}, acc ->
      Logger.debug("validate attribute: #{name}")

      validate_data(acc, name, attribute, data[Atom.to_string(name)])
    end)
  end

  defp validate_data(acc, name, attribute, value) when is_binary(value) do
    validate_data_type(acc, name, attribute, value, @string_types)
  end

  defp validate_data(acc, name, attribute, value) when is_integer(value) do
    validate_data_type(acc, name, attribute, value, @integer_types)
  end

  defp validate_data(acc, name, attribute, value) when is_float(value) do
    validate_data_type(acc, name, attribute, value, @float_types)
  end

  defp validate_data(acc, name, attribute, value) when is_boolean(value) do
    validate_data_type(acc, name, attribute, value, @boolean_types)
  end

  defp validate_data(acc, name, attribute, value) when is_map(value) do
    type = attribute.type

    case type do
      "object_t" -> validate_object(acc, name, attribute, value)
      "json_t" -> acc
      _ -> Map.put(acc, name, invalid_data_type(attribute, value, type))
    end
  end

  defp validate_data(acc, name, attribute, value) when is_list(value) do
    type = attribute.type

    case type do
      "json_t" ->
        acc

      _ ->
        if attribute[:is_array] == true do
          validate_array(acc, name, attribute, value)
        else
          Map.put(acc, name, invalid_data_type(attribute, value, type))
        end
    end
  end

  # checks for missing required attributes
  defp validate_data(acc, name, attribute, nil) do
    case attribute[:requirement] do
      "required" ->
        Map.put(acc, name, %{
          :error => "Missing required attribute",
          :schema => cleanup(attribute)
        })

      _ ->
        acc
    end
  end

  defp validate_data(acc, name, attribute, value) do
    Map.put(acc, name, %{
      :error => "Unhanded attribute",
      :value => value,
      :schema => cleanup(attribute)
    })
  end

  defp validate_array(acc, _name, _attribute, []) do
    acc
  end

  defp validate_array(acc, name, attribute, value) do
    Logger.debug("validate array: #{name}")
    type = attribute.type

    case type do
      "json_t" -> acc
      "object_t" -> validate_object_array(acc, name, attribute, value)
      _simple_t -> validate_simple_array(acc, name, attribute, value)
    end
  end

  defp validate_simple_array(acc, name, attribute, value) do
    Logger.debug("validate array: #{name}")

    {map, _count} =
      Enum.reduce(value, {Map.new(), 0}, fn data, {map, count} ->
        {validate_data(map, "#{count}", attribute, data), count + 1}
      end)

    if map_size(map) > 0 do
      map =
        Enum.map(map, fn {key, data} -> {key, data.value} end)
        |> Map.new()

      Map.put(acc, name, %{
        :error => "Invalid data: expected #{attribute.type} type",
        :values => map,
        :schema => cleanup(attribute)
      })
    else
      acc
    end
  end

  defp validate_object_array(acc, name, attribute, value) do
    object =
      attribute[:object_type]
      |> Schema.objects()

    {map, _count} =
      Enum.reduce(value, {Map.new(), 0}, fn data, {map, count} ->
        result = validate_type(object, data)

        map =
          if map_size(result) > 0 do
            Map.put(map, "#{count}", result)
          else
            map
          end

        {map, count + 1}
      end)

    if map_size(map) > 0 do
      Map.put(acc, name, %{
        :error => "The array contains invalid data",
        :values => map
      })
    else
      acc
    end
  end

  defp validate_object(acc, name, attribute, value) do
    attribute[:object_type]
    |> Schema.objects()
    |> validate_type(value)
    |> valid?(acc, name)
  end

  defp valid?(map, acc, name) do
    if map_size(map) > 0 do
      Map.put(acc, name, map)
    else
      acc
    end
  end

  # check the attribute value type
  defp validate_data_type(acc, name, attribute, value, types) do
    type = attribute.type

    case member?(types, type) do
      nil ->
        Map.put(acc, name, invalid_data_type(attribute, value, type))

      _ ->
        acc
    end
  end

  defp invalid_data_type(attribute, value, type) do
    %{
      :error => "Invalid data: expected #{type} type",
      :value => value,
      :schema => cleanup(attribute)
    }
  end

  defp member?(types, type) do
    Enum.find(types, fn t -> t == type end)
  end

  defp cleanup(attribute) do
    Map.delete(attribute, :_links)
  end
end
