# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Inspector do
  @moduledoc """
  OCSF Event data inspector.
  """

  require Logger

  alias Schema.Utils

  @class_uid "class_uid"

  @string_types [
    "email_t",
    "file_hash_t",
    "file_name_t",
    "hostname_t",
    "ip_t",
    "json_t",
    "mac_t",
    "path_t",
    "process_name_t",
    "resource_uid_t",
    "string_t",
    "subnet_t",
    "url_t",
    "username_t",
    "datetime_t"
  ]

  @integer_types ["port_t", "timestamp_t", "long_t", "json_t"]
  @float_types ["float_t", "json_t"]
  @boolean_types ["boolean_t", "json_t"]

  @doc """
  Validates the given event using `class_uid` value and the schema.
  """
  @spec validate(map()) :: map()
  def validate(data) when is_map(data), do: data[@class_uid] |> validate_class(data)
  def validate(_data), do: %{:error => "Not a JSON object"}

  defp validate_class(nil, _data), do: %{:error => "Missing class_uid"}

  defp validate_class(class_uid, data),
    do: validate_type(Schema.find_class(class_uid), data, data["profiles"])

  defp validate_object(type, data), do: validate_type(type, data, data["profiles"])

  defp validate_type(nil, data, _profiles) do
    class_uid = data[@class_uid]
    %{:error => "Unknown class_uid: #{class_uid}", :value => class_uid}
  end

  defp validate_type(type, data, profiles) do
    attributes = type[:attributes] |> Utils.apply_profiles(profiles)

    Enum.reduce(attributes, %{}, fn {name, attribute}, acc ->
      validate_data(acc, name, attribute, data[Atom.to_string(name)], nil)
    end)
    |> undefined_attributes(attributes, data)
  end

  defp undefined_attributes(acc, attributes, data) do
    Enum.reduce(data, acc, fn {key, value}, map ->
      case attributes[String.to_atom(key)] do
        nil ->
          Map.put(map, key, %{:error => "Undefined attribute name", :value => value})

        _attribute ->
          map
      end
    end)
  end

  defp validate_data(acc, name, attribute, value, _profiles) when is_binary(value) do
    case attribute[:type] do
      "string_t" ->
        case validate_enum_value(attribute[:enum], value) do
          :ok -> acc
          error -> Map.put(acc, name, error)
        end

      _ ->
        validate_data_type(acc, name, attribute, value, @string_types)
    end
  end

  defp validate_data(acc, name, attribute, value, _profiles) when is_integer(value) do
    case attribute[:type] do
      "integer_t" ->
        case validate_enum(attribute[:enum], attribute, value) do
          :ok -> acc
          error -> Map.put(acc, name, error)
        end

      _ ->
        validate_data_type(acc, name, attribute, value, @integer_types)
    end
  end

  defp validate_data(acc, name, attribute, value, _profiles) when is_float(value) do
    validate_data_type(acc, name, attribute, value, @float_types)
  end

  defp validate_data(acc, name, attribute, value, _profiles) when is_boolean(value) do
    validate_data_type(acc, name, attribute, value, @boolean_types)
  end

  defp validate_data(acc, name, attribute, value, _profiles) when is_map(value) do
    case attribute[:type] do
      "object_t" -> validate_object(acc, name, attribute, value)
      "json_t" -> acc
      type -> Map.put(acc, name, invalid_data_type(attribute, value, type))
    end
  end

  defp validate_data(acc, name, attribute, value, profiles) when is_list(value) do
    case attribute[:type] do
      "json_t" ->
        acc

      type ->
        if attribute[:is_array] == true do
          validate_array(acc, name, attribute, value, profiles)
        else
          Map.put(acc, name, invalid_data_type(attribute, value, type))
        end
    end
  end

  # checks for missing required attributes
  defp validate_data(acc, name, attribute, nil, _profiles) do
    case attribute[:requirement] do
      "required" ->
        Map.put(acc, name, %{
          :error => "Missing required attribute"
        })

      _ ->
        acc
    end
  end

  defp validate_data(acc, name, _attribute, value, _profiles) do
    Map.put(acc, name, %{
      :error => "Unhanded attribute",
      :value => value
    })
  end

  defp validate_array(acc, _name, _attribute, [], _profiles) do
    acc
  end

  defp validate_array(acc, name, attribute, value, profiles) do
    Logger.debug("validate array: #{name}")

    case attribute[:type] do
      "json_t" -> acc
      "object_t" -> validate_object_array(acc, name, attribute, value)
      _simple_type -> validate_simple_array(acc, name, attribute, value, profiles)
    end
  end

  defp validate_simple_array(acc, name, attribute, value, profiles) do
    {map, _count} =
      Enum.reduce(value, {Map.new(), 0}, fn data, {map, count} ->
        {validate_data(map, Integer.to_string(count), attribute, data, profiles), count + 1}
      end)

    if map_size(map) > 0 do
      error =
        if attribute[:enum] == nil do
          "The array contains invalid data: expected #{attribute[:type]} type"
        else
          "The array contains invalid enum values"
        end

      values = Enum.into(map, %{}, fn {key, data} -> {key, data.value} end)

      Map.put(acc, name, %{
        :error => error,
        :values => values
      })
    else
      acc
    end
  end

  defp validate_object_array(acc, name, attribute, value) do
    case attribute[:object_type] do
      "object" ->
        acc

      object_type ->
        object = Schema.object(object_type)

        {map, _count} =
          Enum.reduce(value, {Map.new(), 0}, fn data, {map, count} ->
            map = validate_object(object, data) |> add_count(map, count)

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
  end

  defp add_count(result, map, count) do
    if map_size(result) > 0 do
      Map.put(map, "#{count}", result)
    else
      map
    end
  end

  defp validate_object(acc, name, attribute, value) do
    case attribute[:object_type] do
      "object" ->
        acc

      object_type ->
        Schema.object(object_type)
        |> validate_object(value)
        |> valid?(acc, name)
    end
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
    type = attribute[:type]

    case member?(types, type) do
      nil ->
        Map.put(acc, name, invalid_data_type(attribute, value, type))

      _ ->
        acc
    end
  end

  defp invalid_data_type(_attribute, value, type) do
    %{
      :error => "Invalid data: expected #{type} type",
      :value => value
    }
  end

  defp member?(types, type) do
    Enum.find(types, fn t -> t == type end)
  end

  # Validate an integer enum value
  defp validate_enum(nil, _attribute, _value), do: :ok

  defp validate_enum(enum, _attribute, value) do
    validate_enum_value(enum, Integer.to_string(value))
  end

  defp validate_enum_value(nil, _value), do: :ok

  defp validate_enum_value(enum, value) do
    if Map.has_key?(enum, String.to_atom(value)) do
      :ok
    else
      %{
        :error => "Invalid enum value",
        :value => value
      }
    end
  end
end
