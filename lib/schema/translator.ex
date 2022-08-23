# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Translator do
  @moduledoc """
  Translates events to more user friendly form.
  """
  require Logger

  def translate(data, options) when is_map(data) do
    Logger.debug("translate event: #{inspect(data)}, options: #{inspect(options)}")

    case data[:class_uid] do
      nil ->
        translate_class(data["class_uid"], data, options)

      class_uid ->
        translate_class(class_uid, data, options)
    end
  end

  # this is not an event
  def translate(data, _options), do: data

  # missing class_uid, thus cannot translate the event
  defp translate_class(nil, data, _options), do: data

  defp translate_class(class_uid, data, options) do
    translate_event(Schema.find_class(class_uid), data, options)
  end

  # unknown event class, thus cannot translate the event
  defp translate_event(nil, data, _options), do: data

  defp translate_event(type, data, options) do
    attributes = type[:attributes]

    Enum.reduce(data, %{}, fn {key, value}, acc ->
      Logger.debug("#{key}: #{inspect(value)}")

      case attributes[to_atom(key)] do
        nil ->
          # Attribute name is not defined in the schema
          Map.put(acc, key, value)

        attribute ->
          {name, text} = translate_attribute(attribute[:type], key, attribute, value, options)
          Map.put(acc, name, text)
      end
    end)
  end

  defp to_atom(key) when is_atom(key), do: key
  defp to_atom(key), do: String.to_atom(key)

  defp translate_attribute("integer_t", name, attribute, value, options) do
    translate_integer(attribute[:enum], name, attribute, value, options)
  end

  defp translate_attribute("object_t", name, attribute, value, options) when is_map(value) do
    translated = translate_event(Schema.object(attribute[:object_type]), value, options)
    translate_attribute(name, attribute, translated, options)
  end

  defp translate_attribute("object_t", name, attribute, value, options) when is_list(value) do
    obj_type = Schema.object(attribute[:object_type])

    translated =
      Enum.map(value, fn data ->
        translate_event(obj_type, data, options)
      end)

    translate_attribute(name, attribute, translated, options)
  end

  defp translate_attribute(_, name, attribute, value, options),
    do: translate_attribute(name, attribute, value, options)

  # Translate an integer value
  defp translate_integer(nil, name, attribute, value, options),
    do: translate_attribute(name, attribute, value, options)

  # Translate a single enum value
  defp translate_integer(enum, name, attribute, value, options) when is_integer(value) do
    item = Integer.to_string(value) |> String.to_atom()

    translated =
      case enum[item] do
        nil -> value
        map -> map[:caption]
      end

    translate_enum(name, attribute, value, translated, options)
  end

  # Translate an array of enum values
  defp translate_integer(enum, name, attribute, value, options) when is_list(value) do
    Logger.debug("translate_integer: #{name}")

    translated =
      Enum.map(value, fn n ->
        item = Integer.to_string(n) |> String.to_atom()

        case enum[item] do
          nil -> n
          map -> map[:caption]
        end
      end)

    translate_enum(name, attribute, value, translated, options)
  end

  # Translate a non-integer value
  defp translate_integer(_, name, attribute, value, options),
    do: translate_attribute(name, attribute, value, options)

  defp translate_attribute(name, attribute, value, options) do
    case Keyword.get(options, :verbose) do
      2 ->
        {to_text(attribute[:caption], options), value}

      3 ->
        {name,
         %{
           "name" => to_text(attribute[:caption], options),
           "type" => attribute[:object_type] || attribute[:type],
           "value" => value
         }}

      _ ->
        {name, value}
    end
  end

  defp translate_enum(name, attribute, value, translated, options) do
    Logger.debug("translate_enum: #{name}: #{value}")

    case Keyword.get(options, :verbose) do
      1 ->
        {name, translated}

      2 ->
        {to_text(attribute[:caption], options), translated}

      3 ->
        {name,
         %{
           "name" => to_text(attribute[:caption], options),
           "type" => attribute[:object_type] || attribute[:type],
           "value" => value,
           "caption" => translated
         }}

      _ ->
        {name, value}
    end
  end

  defp to_text(name, options) do
    case Keyword.get(options, :spaces) do
      nil -> name
      ch -> String.replace(name, " ", ch)
    end
  end
end
