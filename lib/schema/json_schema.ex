# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.JsonSchema do
  @moduledoc """
  Json schema generator. This module defines functions that generate JSON schema (see http://json-schema.org) schemas for OCSF schema.
  """
  @schema_base_uri "https://schema.ocsf.io/schema/classes"
  @schema_version "http://json-schema.org/draft-07/schema"

  @doc """
  Generates a JSON schema corresponding to the `type` parameter.
  The `type` can be either a class or an object defintion.

  Options: :package_name | :schema_version
  """
  @spec encode(map(), nil | Keyword.t()) :: map()
  def encode(item, options) when is_map(item) do
    Process.put(:options, options || [])

    data_types = Schema.clean_data_types_attributes()

    try do
      encode_item(item, data_types)
    after
      Process.delete(:options)
    end
  end

  def encode(nil, _) do
    %{}
  end

  @spec encode_item(map(), map()) :: map()
  defp encode_item(item, data_types) do
    name = item[:name]

    {properties, required, just_one, at_least_one} = map_reduce(name, item, data_types)

    if Map.has_key?(item, :uid) do
      class_schema(make_class_ref(name))
    else
      Map.new()
      |> add_java_class(name)
      |> add_object_id(name)
    end
    |> Map.put("title", item[:caption])
    |> Map.put("type", "object")
    |> Map.put("properties", properties)
    |> Map.put("additionalProperties", false)
    |> put_required(required)
    |> put_just_one(just_one)
    |> put_at_least_one(at_least_one)
    |> encode_objects(item[:objects], data_types)
    |> empty_object(properties)
  end

  defp add_object_id(obj, name) do
    ref_base =
      Process.get(:options, [])
      |> Keyword.get(:ref_base)

    case ref_base do
      nil -> obj
      _ -> obj |> Map.put("$id", make_object_ref(name)) |> Map.put("$schema", @schema_version)
    end
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
      "$id" => id,
      "additionalProperties" => false
    }
  end

  defp make_object_ref(name) do
    base =
      Process.get(:options, [])
      |> Keyword.get(:ref_base, "#/$defs")

    endpoint =
      Process.get(:options, [])
      |> Keyword.get(:ref_endpoint_objects, "")

    Path.join([base, endpoint, String.replace(name, "/", "_")])
  end

  defp make_class_ref(name) do
    base =
      Process.get(:options, [])
      |> Keyword.get(:ref_base, @schema_base_uri)

    endpoint =
      Process.get(:options, [])
      |> Keyword.get(:ref_endpoint_classes, "")

    Path.join([base, endpoint, name])
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
    Map.put(map, "required", Enum.sort(required))
  end

  defp put_just_one(map, []) do
    map
  end

  defp put_just_one(map, just_one) do
    one_of =
      Enum.map(just_one, fn item ->
        others = Enum.reject(just_one, &(&1 == item))

        %{
          "required" => [item],
          "not" => %{"required" => others}
        }
      end)

    Map.put(map, "oneOf", one_of)
  end

  defp put_at_least_one(map, []) do
    map
  end

  defp put_at_least_one(map, at_least_one) do
    any_of =
      Enum.map(at_least_one, fn item ->
        %{"required" => [item]}
      end)

    Map.put(map, "anyOf", any_of)
  end

  defp encode_objects(schema, nil, _data_types) do
    schema
  end

  defp encode_objects(schema, [], _data_types) do
    schema
  end

  defp encode_objects(schema, objects, data_types) do
    ref_base =
      Process.get(:options, [])
      |> Keyword.get(:ref_base)

    defs =
      Enum.into(objects, %{}, fn {name, object} ->
        key = Atom.to_string(name) |> String.replace("/", "_")
        {key, encode_item(object, data_types)}
      end)

    case ref_base do
      nil -> Map.put(schema, "$defs", defs)
      _ -> schema
    end
  end

  defp map_reduce(type_name, type, data_types) do
    {properties, {required, just_one, at_least_one}} =
      Enum.map_reduce(
        Enum.sort_by(type[:attributes], fn {k, _} -> k end, :desc),
        {[], [], []},
        fn {key, attribute}, {required, just_one, at_least_one} ->
          name = Atom.to_string(key)
          just_one_list = List.wrap(type[:constraints][:just_one])
          at_least_one_list = List.wrap(type[:constraints][:at_least_one])

          cond do
            name in Enum.sort(just_one_list) ->
              {required, [name | just_one], at_least_one}

            name in Enum.sort(at_least_one_list) ->
              {required, just_one, [name | at_least_one]}

            attribute[:requirement] == "required" ->
              {[name | required], just_one, at_least_one}

            true ->
              {required, just_one, at_least_one}
          end
          |> (fn {required, just_one, at_least_one} ->
                schema =
                  encode_attribute(type_name, attribute[:type], attribute, data_types)
                  |> encode_format(attribute[:type])
                  |> encode_array(attribute[:is_array])
                  |> encode_java_names(name)

                {{name, schema}, {required, just_one, at_least_one}}
              end).()
        end
      )

    {Map.new(properties), required, just_one, at_least_one}
  end

  defp encode_attribute(_name, "integer_t", attr, _data_types) do
    new_schema(attr) |> encode_integer(attr)
  end

  defp encode_attribute(_name, "string_t", attr, _data_types) do
    new_schema(attr) |> encode_string(attr)
  end

  defp encode_attribute(name, "object_t", attr, _data_types) do
    new_schema(attr) |> encode_object(name, attr)
  end

  defp encode_attribute(_name, "json_t", attr, _data_types) do
    new_schema(attr)
  end

  defp encode_attribute(_name, type, attr, data_types) do
    new_schema(attr) |> Map.put("type", encode_type(data_types, type))
  end

  defp new_schema(attr), do: %{"title" => attr[:caption]}

  @spec encode_type(map(), String.t()) :: String.t()
  defp encode_type(data_types, type) do
    cond do
      Schema.data_type?(data_types, type, "string_t") -> "string"
      Schema.data_type?(data_types, type, "integer_t") -> "integer"
      Schema.data_type?(data_types, type, "long_t") -> "integer"
      Schema.data_type?(data_types, type, "float_t") -> "number"
      Schema.data_type?(data_types, type, "boolean_t") -> "boolean"
      true -> type
    end
  end

  defp encode_object(schema, _name, attr) do
    type = attr[:object_type]
    Map.put(schema, "$ref", make_object_ref(type))
  end

  defp encode_integer(schema, attr) do
    encode_enum(schema, attr, "integer", fn name ->
      Atom.to_string(name) |> String.to_integer()
    end)
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
    enum
    |> Map.keys()
    |> Enum.map(fn k ->
      encoder.(k)
    end)
    |> Enum.sort()
  end

  defp encode_array(schema, true) do
    {type, schema} = items_type(schema)

    Map.put(schema, "type", "array") |> Map.put("items", type)
  end

  defp encode_format(schema, type) do
    include_formats =
      Process.get(:options, [])
      |> Keyword.get(:include_formats)

    format =
      Application.get_env(:schema_server, :json_formats)
      |> Keyword.get(String.to_atom(type))

    cond do
      include_formats == nil -> schema
      format == nil -> schema
      true -> Map.put(schema, "format", format)
    end
  end

  defp encode_java_names(schema, name) do
    include_java_names =
      Process.get(:options, [])
      |> Keyword.get(:include_java_names)

    java_name =
      Application.get_env(:schema_server, :json_java_names)
      |> Keyword.get(String.to_atom(name))

    cond do
      include_java_names == nil -> schema
      java_name == nil -> schema
      true -> Map.put(schema, "javaName", java_name)
    end
  end

  defp encode_array(schema, _is_array) do
    schema
  end

  defp items_type(schema) do
    case Map.get(schema, "type") do
      nil ->
        {ref, updated} = Map.pop(schema, "$ref")
        {%{"$ref" => ref}, updated}

      type ->
        case Map.pop(schema, "enum") do
          {nil, updated} ->
            {%{"type" => type}, updated}

          {enum, updated} ->
            {%{"type" => type, "enum" => enum}, updated}
        end
    end
  end
end
