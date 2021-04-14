defmodule Schema.Validator do
  @moduledoc """
  Event validator.
  """
  require Logger

  def validate(data) when is_map(data) do
    data["class_id"] |> validate_class(data)
  end

  # Not an event
  def validate(data), do: %{:error => "Not an event", :data => data}

  # Missing event class
  defp validate_class(nil, data), do: %{:error => "Missing class_id", :data => data}

  defp validate_class(class_id, data) do
    validate_event(class_id, Schema.find_class(class_id), data)
  end

  # Unknown event class
  defp validate_event(class_id, nil, data) do
    %{:error => "Undefined event class", :value => class_id, :data => data}
  end

  defp validate_event(_class_id, class, data) do
    attributes = class[:attributes]

    Enum.reduce(data, %{}, fn {key, value}, acc ->
      Logger.debug("validate: #{key}=#{inspect(value)}")

      case attributes[String.to_atom(key)] do
        nil ->
          Map.put(acc, key, %{:error => "Undefined attribute name", :value => value})

        attribute ->
          case validate_attribute(attribute[:type], Map.delete(attribute, :_links), value) do
            :ok ->
              acc

            error ->
              Map.put(acc, key, error)
          end
      end
    end)
  end

  defp validate_attribute("string_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("string_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("string_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("integer_t", attribute, value) when is_integer(value) do
    case validate_value(attribute, value) do
      :ok -> validate_enum(attribute[:enum], attribute, value)
      err -> err
    end
  end

  defp validate_attribute("integer_t", attribute, value) when is_list(value) do
    case validate_array(attribute, value) do
      :ok -> validate_enum_list(attribute[:enum], attribute, value)
      err -> err
    end
  end

  defp validate_attribute("integer_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("timestamp_t", attribute, value) when is_integer(value),
    do: validate_value(attribute, value)

  defp validate_attribute("timestamp_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("timestamp_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("object_t", attribute, value) when is_map(value) do
    case validate_value(attribute, value) do
      :ok ->
        name = attribute[:object_type]
        map = validate_event(name, Schema.objects(name), value)

        if Enum.empty?(map) do
          :ok
        else
          map
        end

      err ->
        err
    end
  end

  defp validate_attribute("object_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("object_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("long_t", attribute, value) when is_integer(value),
    do: validate_value(attribute, value)

  defp validate_attribute("long_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("long_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("boolean_t", attribute, value) when is_boolean(value),
    do: validate_value(attribute, value)

  defp validate_attribute("boolean_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("boolean_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("hostname_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("hostname_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("hostname_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("email_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("email_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("email_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("mac_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("mac_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("mac_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("path_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("path_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("path_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("port_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("port_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("port_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("ip_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("ip_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("ip_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("ipv4_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("ipv4_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("ipv4_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("ipv6_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("ipv6_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("subnet_t", attribute, value) when is_binary(value),
    do: validate_value(attribute, value)

  defp validate_attribute("subnet_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("subnet_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("ipv6_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("float_t", attribute, value) when is_float(value),
    do: validate_value(attribute, value)

  defp validate_attribute("float_t", attribute, value) when is_list(value),
    do: validate_array(attribute, value)

  defp validate_attribute("float_t", attribute, value), do: invalid_value(attribute, value)

  defp validate_attribute("json_t", _desc, _value), do: :ok

  defp validate_attribute(_, attribute, value) do
    %{:error => "Unexpected data type", :value => value, :attribute => attribute}
  end

  defp is_array(attribute), do: attribute[:is_array] || false

  defp validate_array(attribute, value) do
    if is_array(attribute) do
      type = attribute[:type]
      attribute = Map.delete(attribute, :is_array)

      errors =
        Enum.reduce(value, [], fn item, acc ->
          case validate_attribute(type, attribute, item) do
            :ok -> acc
            err -> [err | acc]
          end
        end)

      if Enum.empty?(errors) do
        :ok
      else
        %{
          :error => "One ore more invalid values",
          :value => value,
          :schema => attribute,
          :errors => errors
        }
      end
    else
      invalid_value(attribute, value)
    end
  end

  defp validate_value(attribute, value) do
    if is_array(attribute) do
      invalid_array(attribute, value)
    else
      :ok
    end
  end

  # Validate a single enum value
  defp validate_enum(nil, _desc, _value), do: :ok

  defp validate_enum(enum, attribute, value) do
    key = Integer.to_string(value) |> String.to_atom()

    if Map.has_key?(enum, key) do
      :ok
    else
      %{:error => "Invalid enum value: #{value}", :value => value, :schema => attribute}
    end
  end

  # Validate an array of enum values
  defp validate_enum_list(nil, _desc, _value), do: :ok

  defp validate_enum_list(enum, attribute, value) do
    values =
      Enum.reduce(value, [], fn n, acc ->
        key = Integer.to_string(n) |> String.to_atom()

        if Map.has_key?(enum, key) do
          acc
        else
          [n | acc]
        end
      end)

    if Enum.empty?(values) do
      :ok
    else
      list = values |> Enum.reverse() |> Jason.encode!()

      %{
        :error => "One ore more invalid enum values: " <> list,
        :value => value,
        :schema => attribute
      }
    end
  end

  defp invalid_array(attribute, value) do
    type = attribute[:type]
    invalid_data(attribute, value, "an array of #{type}s")
  end

  defp invalid_value(attribute, value) do
    invalid_data(attribute, value, attribute[:type])
  end

  defp invalid_data(attribute, value, type) do
    %{:error => "Invalid data: expected #{type} data type", :value => value, :schema => attribute}
  end
end
