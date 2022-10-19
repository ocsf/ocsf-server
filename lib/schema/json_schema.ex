defmodule Schema.JsonSchema do
  @moduledoc """
  Json schema generator. This module defines functions that generate JSON schema (see http://json-schema.org) schemas for OCSF schema.
  """
  @schema_base_uri "https://schema.ocsf.io/schema/classes"
  @schema_version "http://json-schema.org/draft-07/schema#"

  @doc """
  Generates a JSON schema corresponding to the`type` parameter.
  The `type` can be either a class or an object defintion.
  """
  def encode(type) when is_map(type) do
    name = type[:name]

    {properties, required} = map_reduce(name, type[:attributes])

    ext = type[:extension]

    if Map.has_key?(type, :_links) do
      object_schema(make_object_ref(name, ext))
    else
      class_schema(make_class_ref(name, ext))
    end
    |> empty_object(properties)
    |> Map.put("title", type[:caption])
    |> Map.put("type", "object")
    |> Map.put("properties", properties)
    |> put_required(required)
    |> encode_objects(type[:objects])
  end

  defp class_schema(id) do
    %{
      "$schema" => @schema_version,
      "$id" => id
    }
  end

  defp object_schema(id) do
    %{
      "$id" => id
    }
  end

  defp make_object_ref(name) do
    Path.join(["/schema/objects", name])
  end

  defp make_object_ref(name, nil) do
    Path.join(["/schema/objects", name])
  end

  defp make_object_ref(name, ext) do
    Path.join(["/schema/objects", ext, name])
  end

  defp make_class_ref(name, nil) do
    Path.join([@schema_base_uri, name])
  end

  defp make_class_ref(name, ext) do
    Path.join([@schema_base_uri, ext, name])
  end

  defp empty_object(map, properties) do
    if map_size(properties) == 0 do
      Map.put(map, "additionalProperties", true)
    else
      map
    end
  end
  
  defp put_required(map, []) do
    map
  end
  
  defp put_required(map, required) do
    Map.put(map, "required", required)
  end
  
  defp encode_objects(schema, nil) do
    schema
  end

  defp encode_objects(schema, []) do
    schema
  end

  defp encode_objects(schema, objects) do
    defs =
      Enum.into(objects, %{}, fn {name, object} ->
        key = Atom.to_string(name) |> String.replace("/", "_")
        {key, encode(object)}
      end)

    Map.put(schema, "$defs", defs)
  end

  defp object_self_ref(), do: "#"

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

  defp encode_attribute(name, "integer_t", attr) do
    encode_integer(name, attr)
  end

  defp encode_attribute(_name, "json_t", attr) do
    %{"title" => attr[:caption]}
    |> Map.put("oneOf", [
      %{"type" => "string"},
      %{"type" => "integer"},
      %{"type" => "number"},
      %{"type" => "boolean"},
      %{"type" => %{"$ref" => make_object_ref("object")}},
      %{"type" => "array", "items" => %{ "$ref" => "#" }}
    ])
  end

  defp encode_attribute(_name, type, attr) do
    %{"type" => encode_type(type)}
    |> Map.put("title", attr[:caption])
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

  defp encode_type("long_t"), do: "integer"
  defp encode_type("timestamp_t"), do: "integer"
  defp encode_type("port_t"), do: "integer"
  defp encode_type("float_t"), do: "number"

  defp encode_type("boolean_t"), do: "boolean"

  defp encode_type(type), do: type

  defp encode_object(name, attr) do
    object =
      case attr[:object_type] do
        ^name ->
          %{"$ref" => object_self_ref()}

        type ->
          %{"$ref" => make_object_ref(type)}
      end

    case attr[:is_array] do
      true ->
        Map.new()
        |> Map.put("type", "array")
        |> Map.put("items", object)

      _ ->
        object
    end
  end

  defp encode_integer(_name, attr) do
    value = %{"title" => attr[:caption]}

    case attr[:enum] do
      nil ->
        Map.put(value, "type", "integer")

      enum ->
        case encode_enum_values(enum) do
          [uid] ->
            Map.put(value, "const", uid)

          values ->
            Map.put(value, "enum", values)
        end
    end
  end

  defp encode_enum_values(enum) do
    Enum.map(enum, fn {name, _} ->
      enum_value_integer(name)
    end)
  end

  defp enum_value_integer(name), do: Atom.to_string(name) |> String.to_integer()
end
