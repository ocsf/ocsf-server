defmodule Schema.JsonSchema do
  @moduledoc """
  Json schema generator. This module defines functions that generate JSON schema (see http://json-schema.org) schemas for OCSF schema.
  """
  require Logger

  @base_uri "https://schema.ocsf.io/schema"

  def schema() do
    %{
      "$id" => @base_uri,
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "additionalProperties" => true
    }
  end

  @doc """
  Generates a JSON schema corresponding to the`type` parameter.
  The `type` can be either a class or an object defintion.
  """
  def encode(type) when is_map(type) do
    name = type[:name]

    {properties, required} = map_reduce(name, type[:attributes])

    Logger.info("encode json schema: #{name}")

    if Map.has_key?(type, :_links) do
      schema(make_object_ref(name))
    else
      schema(make_class_ref(name))
    end
    |> Map.put("type", "object")
    |> Map.put("properties", properties)
    |> Map.put("required", required)
  end

  defp schema(id) do
    %{
      "$id" => id,
      "additionalProperties" => true
    }
  end

  defp object_self_ref(), do: "#"

  defp make_object_ref(name) do
    Path.join(["/schema/objects"], name)
  end

  defp make_class_ref(name) do
    Path.join(["/schema/classes"], name)
  end

  defp map_reduce(type_name, attributes) do
    {properties, required} =
      Enum.map_reduce(attributes, [], fn {key, attribute}, acc ->
        name = Atom.to_string(key)

        acc =
          case attribute[:requirement] do
            "required" -> [name | acc]
            _ -> acc
          end

        {{name, encode_attribute(type_name, attribute[:type], attribute)}, acc}
      end)

    {Map.new(properties), required}
  end

  defp encode_attribute(name, "object_t", attr) do
    encode_object(name, attr)
  end

  defp encode_attribute(_name, type, _attr) do
    %{"type" => encode_type(type)}
  end

  defp encode_type("string_t"), do: "string"
  defp encode_type("datetime_t"), do: "string"
  defp encode_type("email_t"), do: "string"
  defp encode_type("file_hash_t"), do: "string"
  defp encode_type("file_name_t"), do: "string"
  defp encode_type("hostname_t"), do: "string"
  defp encode_type("ip_t"), do: "string"
  defp encode_type("mac_t"), do: "string"
  defp encode_type("path_t"), do: "string"
  defp encode_type("process_name_t"), do: "string"
  defp encode_type("resource_uid_t"), do: "string"
  defp encode_type("subnet_t"), do: "string"
  defp encode_type("url_t"), do: "string"
  defp encode_type("username_t"), do: "string"

  defp encode_type("integer_t"), do: "integer"
  defp encode_type("long_t"), do: "integer"
  defp encode_type("timestamp_t"), do: "integer"
  defp encode_type("port_t"), do: "integer"

  defp encode_type("float_t"), do: "number"

  defp encode_type("boolean_t"), do: "boolean"

  defp encode_type(type), do: type

  defp encode_object(name, atribute) do
    object =
      case atribute[:object_type] do
        ^name ->
          %{"$ref" => object_self_ref()}

        type ->
          %{"$ref" => make_object_ref(type)}
      end

    case atribute[:is_array] do
      true ->
        object
        |> Map.put("type", "array")
        |> Map.put("items", object)

      _ ->
        object
    end

    # |> Map.put("requirement", atribute[:requirement])
  end
end
