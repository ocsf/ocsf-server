# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule SchemaWeb.SchemaController do
  @moduledoc """
  The Event Schema API.
  """

  use SchemaWeb, :controller

  import PhoenixSwagger

  require Logger

  @verbose "_mode"
  @spaces "_spaces"

  # -------------------
  # Event Schema API's
  # -------------------

  def swagger_definitions do
    %{
      Version:
        swagger_schema do
          title("Version")
          description("Schema version, using Semantic Versioning Specification (SemVer) format.")

          properties do
            version(:string, "Version number", required: true)
          end

          example(%{
            version: "1.0.0"
          })
        end
    }
  end

  @doc """
  Get the OCSF schema version.
  get /api/version

  Example usage:
    curl https://schema.ocsf.io/api/version

    Success-Response:
    HTTP/2 200 OK
    {
      "version": "0.16.0"
    }
  """
  swagger_path :version do
    get("/version")
    summary("Version")
    produces("application/json")
    description("Get OCSF schema version.")
    response(200, "Success", :Version)
  end

  @spec version(Plug.Conn.t(), any) :: Plug.Conn.t()
  def version(conn, _params) do
    version = %{:version => Schema.version()}
    send_json_resp(conn, version)
  end

  @doc """
  Get the schema data types.
  get /api/data_types

  Example usage:
    curl https://schema.ocsf.io/api/data_types

    Success-Response:
    HTTP/2 200 OK
    {
      "boolean_t": {
        "caption": "Boolean",
        "description": "Boolean value. One of <code>true</code> or <code>false</code>.",
        "values": [
          false,
          true
        ]
      },
      ...
    }
  """
  swagger_path :data_types do
    get("/data_types")
    summary("Data Types")
    produces("application/json")
    description("Get OCSF schema data types.")
    response(200, "Success")
  end

  @spec data_types(Plug.Conn.t(), any) :: Plug.Conn.t()
  def data_types(conn, _params) do
    send_json_resp(conn, Schema.export_data_types())
  end

  @doc """
  Get the schema extensions.
  get /api/extensions

  Example usage:
    curl https://schema.ocsf.io/api/extensions

    Success-Response:
    HTTP/2 200 OK
    {
      "dev": {
        "caption": "Development",
        "name": "dev",
        "uid": 999,
        "version": "0.0.0"
      }
    }
  """
  swagger_path :extensions do
    get("/extensions")
    summary("Schema Extensions")
    produces("application/json")
    description("Get OCSF schema extensions.")
    response(200, "Success")
  end

  @spec extensions(Plug.Conn.t(), any) :: Plug.Conn.t()
  def extensions(conn, _params) do
    extensions =
      Schema.extensions()
      |> Enum.into(%{}, fn {k, v} ->
        {k, Map.delete(v, :path)}
      end)

    send_json_resp(conn, extensions)
  end

  @doc """
  Get the schema profiles.
  get /api/profiles

  Example usage:
    curl https://schema.ocsf.io/api/profiles

    Success-Response:
    HTTP/2 200 OK
    {
      "cloud": {
        "caption": "Cloud",
        "attributes": {
          "cloud": {
            "requirement": "required"
          }
        }
      },
      ...
    }
  """
  swagger_path :profiles do
    get("/profiles")
    summary("Schema Profiles")
    produces("application/json")
    description("Get OCSF schema profiles.")
    response(200, "Success")
  end

  @spec profiles(Plug.Conn.t(), any) :: Plug.Conn.t()
  def profiles(conn, _params) do
    send_json_resp(conn, Schema.profiles())
  end

  @doc """
  Get the classes defined in a given category.
  get /api/categories/:name

  Example usage:
    curl https://schema.ocsf.io/api/categories/database

    Success-Response:
    HTTP/2 200 OK
    {
      "caption": "Database Activity",
      "classes": {
        "database_lifecycle": {
          "caption": "Database Lifecycle",
          "description": "Database Lifecycle events report start and stop of a database service.",
          "name": "database_lifecycle",
          "uid": 7000
        }
      },
      "description": "Database Activity events.",
      "uid": 7
    }
  """
  swagger_path :categories do
    get("/categories/{name}")
    summary("Category Classes")
    produces("application/json")
    description("Get OCSF schema classes defined in the named category.")

    parameters do
      name(:path, :string, "Category name", required: true)
    end

    response(200, "Success")
    response(404, "Category <code>name</code> not found")
  end

  @spec categories(Plug.Conn.t(), map) :: Plug.Conn.t()
  def categories(conn, %{"id" => id} = params) do
    try do
      case category_classes(params) do
        nil ->
          send_json_resp(conn, 404, %{error: "Category #{id} not found"})

        data ->
          send_json_resp(conn, data)
      end
    rescue
      e ->
        Logger.error("Unable to load the classes for category: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /api/categories Get Categories
  # @apiName Categories
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  @doc """
  Get the schema categories.
  get /api/categories

  Example usage:
    curl https://schema.ocsf.io/api/categories

    Success-Response:
    HTTP/2 200 OK
    {
      "caption": "Database Activity",
      "classes": {
        "database_lifecycle": {
          "caption": "Database Lifecycle",
          "description": "Database Lifecycle events report start and stop of a database service.",
          "name": "database_lifecycle",
          "uid": 7000
        }
      },
      "description": "Database Activity events.",
      "uid": 7
    }
  """
  #  swagger_path :categories do
  #    get("/categories")
  #    summary("Categories")
  #    produces("application/json")
  #    description("Get OCSF schema categories.")
  #    response(200, "Success")
  #  end
  def categories(conn, params) do
    send_json_resp(conn, categories(params))
  end

  @spec categories(map()) :: map()
  def categories(params) do
    parse_options(extensions(params)) |> Schema.categories()
  end

  @spec category_classes(map()) :: map() | nil
  def category_classes(params) do
    name = params["id"]
    extension = extension(params)
    extensions = parse_options(extensions(params))

    Schema.category(extensions, extension, name)
  end

  # {
  # @api {get} /api/dictionary Get Dictionary
  # @apiName Dictionary
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  @doc """
  Renders the attribute dictionary.
  """
  @spec dictionary(Plug.Conn.t(), any) :: Plug.Conn.t()
  def dictionary(conn, params) do
    data = dictionary(params) |> remove_links(:attributes)

    send_json_resp(conn, data)
  end

  @doc """
  Renders the dictionary.
  """
  @spec dictionary(map) :: map
  def dictionary(params) do
    parse_options(extensions(params)) |> Schema.dictionary()
  end

  # {
  # @api {get} /api/base_event Get Base Event
  # @apiName Base Event
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  @doc """
  Renders the base event attributes.
  """
  @spec base_event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def base_event(conn, params) do
    base = Schema.class(:base_event) |> add_objects(params)

    send_json_resp(conn, base)
  end

  # {
  # @api {get} /api/classes/:type Get Class
  # @apiName Class
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} type Event class type name, for example: `mem_usage`
  # }
  @doc """
  Renders  an event class.
  """
  @spec classes(Plug.Conn.t(), any) :: Plug.Conn.t()
  def classes(conn, %{"id" => id} = params) do
    extension = extension(params)

    try do
      case Schema.class(extension, id, parse_options(profiles(params))) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          class = Schema.delete_see_also(data) |> add_objects(params)
          send_json_resp(conn, class)
      end
    rescue
      e ->
        Logger.error("Unable to get class: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /api/classes Get Classes
  # @apiName Class
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  def classes(conn, params) do
    classes =
      Enum.map(classes(params), fn {_name, class} ->
        Schema.reduce_class(class)
      end)

    send_json_resp(conn, classes)
  end

  @spec classes(map) :: map
  def classes(params) do
    extensions = parse_options(extensions(params))

    case parse_options(profiles(params)) do
      nil ->
        Schema.classes(extensions)

      profiles ->
        Schema.classes(extensions, profiles)
    end
  end

  # {
  # @api {get} /api/objects/:type Get Object
  # @apiName Object
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} type Object type name, for example: `container`
  # }
  @doc """
  Renders objects.
  """
  @spec objects(Plug.Conn.t(), map) :: Plug.Conn.t()
  def objects(conn, %{"id" => id} = params) do
    try do
      case object(params) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          send_json_resp(conn, add_objects(data, params))
      end
    rescue
      e ->
        Logger.error("Unable to get object: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /api/objects Get Objects
  # @apiName Objects
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  def objects(conn, params) do
    objects =
      Enum.map(objects(params), fn {_name, map} ->
        Map.delete(map, :_links) |> Schema.delete_attributes()
      end)

    send_json_resp(conn, objects)
  end

  @spec objects(map) :: map
  def objects(params) do
    parse_options(extensions(params)) |> Schema.objects()
  end

  @spec object(map) :: map() | nil
  def object(%{"id" => id} = params) do
    profiles = parse_options(profiles(params))
    extension = extension(params)
    extensions = parse_options(extensions(params))

    Schema.object(extensions, extension, id, profiles)
  end

  # -------------------
  # Schema Export API's
  # -------------------

  #
  #   @apiSuccess {Object} classes The OCSF schema classes.
  #   @apiSuccess {Object} objects The OCSF schema obejcts.
  #   @apiSuccess {Object} types The OCSF schema data types.
  #   @apiSuccess {String} version The OCSF schema version.
  #  
  @doc """
  Export the OCSF schema definitions.
  get /export/schema

  Example usage:
    curl https://schema.ocsf.io/export/schema

    Success-Response:
    HTTP/2 200 OK
    {
      "classes": {...},
      "objects": {...},
      "types"  : {...},
      "version": "0.16.0"
    }
  """
  swagger_path :export_schema do
    get("/export/schema")
    summary("Export Schema")
    produces("application/json")
    description("Get OCSF schema defintions, including data types, objects, and classes.")

    parameters do
      extensions(:query, :array, "Related extensions to include in response",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response", items: [type: :string])
    end

    response(200, "Success")
  end

  @spec export_schema(Plug.Conn.t(), any) :: Plug.Conn.t()
  def export_schema(conn, params) do
    profiles = parse_options(profiles(params))
    data = parse_options(extensions(params)) |> Schema.export_schema(profiles)
    send_json_resp(conn, data)
  end

  @doc """
  Export the OCSF schema classes.
  get /export/classes

  Example usage:
    curl https://schema.ocsf.io/export/classes

    Success-Response:
    HTTP/2 200 OK
    {
      ...
    }
  """
  swagger_path :export_classes do
    get("/export/classes")
    summary("Export Classes")
    produces("application/json")
    description("Get OCSF schema classes.")

    parameters do
      extensions(:query, :array, "Related extensions to include in response",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response", items: [type: :string])
    end

    response(200, "Success")
  end

  def export_classes(conn, params) do
    profiles = parse_options(profiles(params))
    classes = parse_options(extensions(params)) |> Schema.export_classes(profiles)
    send_json_resp(conn, classes)
  end

  @doc """
  Export the OCSF schema objects.
  get /export/objects

  Example usage:
    curl https://schema.ocsf.io/export/objects

    Success-Response:
    HTTP/2 200 OK
    {
      ...
    }
  """
  swagger_path :export_objects do
    get("/export/objects")
    summary("Export Objects")
    produces("application/json")
    description("Get OCSF schema objects.")

    parameters do
      extensions(:query, :array, "Related extensions to include in response",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response", items: [type: :string])
    end

    response(200, "Success")
  end

  def export_objects(conn, params) do
    profiles = parse_options(profiles(params))
    objects = parse_options(extensions(params)) |> Schema.export_objects(profiles)
    send_json_resp(conn, objects)
  end

  # ---------------------------------
  # Validation and translation API's
  # ---------------------------------

  # {
  # @api {post} /api/translate?_mode=:mode Translate Event
  # @apiName Translate
  # @apiGroup Tools
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {Number=1,2,3} _mode  Controls how the attribute names and enumerated values are translated
  # @apiParam {String} _spaces  Controls how the spaces in the translated attribute names are handled
  # @apiParam {JSON} event  The event to be translated as a JSON object
  #
  # @apiParamExample {json} Request-Example:
  #     {
  #       "class_uid": 1002,
  #       "activity_id": 1,
  #       "severity_id": 1,
  #       "message": "This is an important message"
  #     }
  #
  # @apiSuccessExample {json} Success-Response:
  #     {
  #       "class_uid": "Entity Audit",
  #       "message": "This is an important message",
  #       "activity_id": "Created",
  #       "severity_id": "Informational"
  #     }
  # }
  @spec translate(Plug.Conn.t(), map) :: Plug.Conn.t()
  def translate(conn, data) do
    options = [spaces: data[@spaces], verbose: verbose(data[@verbose])]

    case data["_json"] do
      nil ->
        # Translate a single events
        data =
          Map.delete(data, @verbose)
          |> Map.delete(@spaces)
          |> Schema.Translator.translate(options)

        send_json_resp(conn, data)

      list when is_list(list) ->
        # Translate a list of events
        translated = Enum.map(list, fn data -> Schema.Translator.translate(data, options) end)
        send_json_resp(conn, translated)

      other ->
        # some other json data
        send_json_resp(conn, other)
    end
  end

  # {
  # @api {post} /api/validate Validate Event
  # @apiName Validate
  # @apiGroup Tools
  # @apiVersion 1.0.0
  #
  # @apiDescription The event or events to be translated.
  # A single event is encoded as a JSON object and multiple events are encoded as JSON array of object.
  #
  # @apiParam {Object} event The event or events to be translated.
  # A single event is encoded as a JSON object and multiple events are encoded as JSON array of object.
  #
  # @apiParamExample {json} Request-Example:
  #    {
  #      "id": 4711
  #    }
  #
  # }
  @spec validate(Plug.Conn.t(), map) :: Plug.Conn.t()
  def validate(conn, data) do
    case data["_json"] do
      nil ->
        # Validate a single events
        send_json_resp(conn, Schema.Inspector.validate(data))

      list when is_list(list) ->
        # Validate a list of events
        result = Enum.map(list, fn data -> Schema.Inspector.validate(data) end)
        send_json_resp(conn, result)

      other ->
        # some other json data
        send_json_resp(conn, %{:error => "The data does not look like an event", "data" => other})
    end
  end

  # --------------------------
  # Request sample data API's
  # --------------------------

  @doc """
  Returns a base event sample.
  """
  @spec sample_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_event(conn, _params) do
    send_json_resp(conn, Schema.event(:base_event))
  end

  # {
  #   @api {get} /sample/classes/:name Classs
  #   @apiName Class Sample
  #   @apiDescription This API returns sample data for the given event class name.
  #   @apiGroup Sample
  #   @apiVersion 1.0.0
  #   @apiPermission none
  #   @apiParam {String} name Event class name
  #   @apiQuery {Number=1,2,3} _mode  Controls how the attribute names and enumerated values are translated
  #   @apiQuery {String} _spaces  Controls how the spaces in the translated attribute names are handled
  #   @apiSuccess {JSON} The randomly generated sample data
  # }
  @doc """
  Returns an event sample for the given name.
  """
  @spec sample_class(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_class(conn, %{"id" => id} = options) do
    extension = options["extension"]
    profiles = parse_options(options["profiles"])

    try do
      case Schema.class(extension, id) do
        nil ->
          send_json_resp(conn, 404, %{error: "Class not found: #{id}"})

        class ->
          event =
            case Map.get(options, @verbose) do
              nil ->
                Schema.generate_event(class, profiles)

              verbose ->
                Schema.generate_event(class, profiles)
                |> Schema.Translator.translate(
                  spaces: options[@spaces],
                  verbose: verbose(verbose)
                )
            end

          send_json_resp(conn, event)
      end
    rescue
      e ->
        Logger.error("Unable to generate sample for class: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /sample/objects/:name Object
  # @apiName Object Sample
  # @apiGroup Sample
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} name Object name
  # @apiSuccess {JSON} json The randomly generated sample data
  # }
  @doc """
  Returns an object sample data for the given name.
  """
  @spec sample_object(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_object(conn, %{"id" => id} = options) do
    extension = options["extension"]

    try do
      case Schema.object(extension, id) do
        nil ->
          send_json_resp(conn, 404, %{error: "Object not found: #{id}"})

        data ->
          send_json_resp(conn, Schema.generate(data))
      end
    rescue
      e ->
        Logger.error("Unable to generate sample for object: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  defp send_json_resp(conn, error, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(error, Jason.encode!(data))
  end

  defp send_json_resp(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  defp remove_links(data) do
    data
    |> Schema.delete_links()
    |> remove_links(:attributes)
  end

  defp remove_links(data, key) do
    case data[key] do
      nil ->
        data

      list ->
        updated =
          Enum.map(list, fn {k, v} ->
            %{k => Schema.delete_links(v)}
          end)

        Map.put(data, key, updated)
    end
  end

  defp add_objects(data, %{"objects" => "1"}) do
    objects = update_objects(Map.new(), data[:attributes])

    if map_size(objects) > 0 do
      Map.put(data, :objects, objects)
    else
      data
    end
    |> remove_links()
  end

  defp add_objects(data, _params) do
    remove_links(data)
  end

  defp update_objects(objects, attributes) do
    Enum.reduce(attributes, objects, fn {_name, field}, acc ->
      update_object(field, acc)
    end)
  end

  defp update_object(field, acc) do
    case field[:type] do
      "object_t" ->
        type = field[:object_type] |> String.to_atom()

        if Map.has_key?(acc, type) do
          acc
        else
          object = Schema.object(type)
          Map.put(acc, type, remove_links(object)) |> update_objects(object[:attributes])
        end

      _other ->
        acc
    end
  end

  defp verbose(option) when is_binary(option) do
    case Integer.parse(option) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp verbose(_), do: 0

  defp profiles(params), do: params["profiles"]
  defp extension(params), do: params["extension"]
  defp extensions(params), do: params["extensions"]

  defp parse_options(nil), do: nil
  defp parse_options(""), do: MapSet.new()
  defp parse_options(options), do: String.split(options, ",") |> MapSet.new()
end
