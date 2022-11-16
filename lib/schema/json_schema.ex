defmodule Schema.JsonSchema do
  @moduledoc """
  Json schema generator. This module defines functions that generate JSON schema (see http://json-schema.org) schemas for OCSF schema.
  """
  @schema_base_uri "https://schema.ocsf.io/schema/classes"
  @schema_version "http://json-schema.org/draft-07/schema#"

  @doc """
  Generates a JSON schema corresponding to the `type` parameter.
  The `type` can be either a class or an object defintion.

  Options: :package_name | :schema_version
  """
  @spec encode(map(), nil | Keyword.t()) :: map()
  def encode(type, options) when is_map(type) do
    Process.put(:options, options || [])

    try do
      encode(type)
    after
      Process.delete(:options)
    end
  end

  def encode(type) do
    name = type[:name]

    {properties, required} = map_reduce(name, type[:attributes])

    ext = type[:extension]

    if Map.has_key?(type, :_links) do
      Map.new()
      |> add_java_class(name)
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

  defp add_java_class(obj, name) do
    case Process.get(:options) do
      nil ->
        obj

      options ->
        add_java_class(obj, name, Keyword.get(options, :package_name))
    end
  end

  defp add_java_class(obj, _name, nil) do
    obj
  end

  defp add_java_class(obj, name, package) do
    Map.put(obj, "javaType", make_java_name(package, name))
  end

  defp make_java_name(package, name) do
    name = String.split(name, "_") |> Enum.map_join(fn name -> String.capitalize(name) end)
    "#{package}.#{name}"
  end

  defp class_schema(id) do
    %{
      "$schema" => @schema_version,
      "$id" => id
    }
  end

  defp make_object_ref(name) do
    Path.join([ref_object(), String.replace(name, "/", "_")])
  end

  defp ref_object() do
    "#/$defs"
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
      |> Map.put("json_t", json_type())

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

        schema =
          encode_attribute(type_name, attribute[:type], attribute)
          |> encode_array(attribute[:is_array])

        {{name, schema}, acc}
      end)

    {Map.new(properties), required}
  end

  defp encode_attribute(name, "object_t", attr) do
    new_schema(attr)
    |> encode_object(name, attr)
  end

  defp encode_attribute(_name, "integer_t", attr) do
    new_schema(attr)
    |> encode_integer(attr)
  end

  defp encode_attribute(_name, "string_t", attr) do
    new_schema(attr)
    |> encode_string(attr)
  end

  defp encode_attribute(_name, "json_t", attr) do
    new_schema(attr)
    |> Map.put("$ref", make_object_ref("json_t"))
  end

  defp encode_attribute(_name, type, attr) do
    new_schema(attr)
    |> Map.put("type", encode_type(type))
  end
  
  defp new_schema(attr), do: 
    %{"title" => attr[:caption]}

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

  defp encode_object(schema, name, attr) do
    case attr[:object_type] do
      ^name ->
        Map.put(schema, "$ref", object_self_ref())

      type ->
        Map.put(schema, "$ref", make_object_ref(type))
    end
  end

  defp encode_integer(schema, attr) do
    encode_enum(schema, attr, "integer", fn name -> Atom.to_string(name) |> String.to_integer() end)
  end

  defp encode_string(schema, attr) do
    encode_enum(schema, attr, "string", &Atom.to_string/1)
  end

  defp encode_enum(schema, attr, type, encoder) do
    case attr[:enum] do
      nil ->
        schema

      enum ->
        case encode_enum_values(enum, encoder) do
          [uid] ->
            Map.put(schema, "const", uid)

          values ->
            Map.put(schema, "enum", values)
        end
    end
    |> Map.put("type", type)
  end

  defp encode_enum_values(enum, encoder) do
    Enum.map(enum, fn {name, _} ->
      encoder.(name)
    end)
  end

  defp json_type() do
    %{"title" => "JSON"}
    |> Map.put("oneOf", [
      %{"type" => "string"},
      %{"type" => "integer"},
      %{"type" => "number"},
      %{"type" => "boolean"},
      %{"$ref" => make_object_ref("object")},
      %{"type" => "array", "items" => %{"$ref" => "#"}}
    ])
  end

  defp encode_array(schema, true) do
    type = items_type(schema)

    schema
    |> Map.put("type", "array")
    |> Map.put("items", type)
    |> Map.delete("$ref")
  end

  defp encode_array(schema, _is_array) do
    schema
  end

  defp items_type(schema) do
    case Map.get(schema, "type") do
      nil ->
        %{"$ref" => Map.get(schema, "$ref")}

      type ->
        %{"type" => type}
    end
  end
end
