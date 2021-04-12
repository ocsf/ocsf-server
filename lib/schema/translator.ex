defmodule Schema.Translator do
  @moduledoc """
  Translates events to more user friendly form.
  """
  require Logger

  def translate(data, options) when is_map(data) do
    Logger.debug("translate event: #{inspect(data)}, options: #{inspect(options)}")

    case data[:class_id] do
      nil ->
        translate_class(data["class_id"], data, options)

      class_id ->
        translate_class(class_id, data, options)
    end
  end

  # this is not an event
  def translate(data, _options), do: data

  # missing class_id, thus cannot translate the event
  defp translate_class(nil, data, _options), do: data

  defp translate_class(class_id, data, options) do
    translate_event(Schema.find_class(class_id), data, options)
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
    translated = translate_event(Schema.objects(attribute[:object_type]), value, options)
    translate_attribute(name, attribute, translated, options)
  end

  defp translate_attribute("object_t", name, attribute, value, options) when is_list(value) do
    obj_type = Schema.objects(attribute[:object_type])

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
        nil -> translate_category_id(name, value)
        map -> map[:name]
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
          map -> map[:name]
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
        {to_text(attribute[:name], options), value}

      3 ->
        {name,
         %{
           "_name" => to_text(attribute[:name], options),
           "_type" => attribute[:type],
           "_value" => value
         }}

      _ ->
        {name, value}
    end
  end

  defp translate_enum(name, attribute, value, translated, options) do
    Logger.debug("translate_enum: #{name}: #{value}")

    case Keyword.get(options, :verbose) do
      2 ->
        {to_text(attribute[:name], options), translated}

      3 ->
        {name,
         %{
           "_name" => to_text(attribute[:name], options),
           "_type" => attribute[:type],
           "_value" => value,
           "_enum" => translated
         }}

      _ ->
        {name, translated}
    end
  end

  defp to_text(name, options) do
    case Keyword.get(options, :spaces) do
      nil -> name
      ch -> String.replace(name, " ", ch)
    end
  end

  defp translate_category_id("category_id", value) do
    Schema.find_categoriy(value) || value
  end

  defp translate_category_id(_name, value) do
    value
  end
end
