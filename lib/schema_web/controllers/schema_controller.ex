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

  @enum_text "_enum_text"
  @observables "_observables"

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
        end,
      Versions:
        swagger_schema do
          title("Versions")
          description("Schema versions, using Semantic Versioning Specification (SemVer) format.")

          properties do
            versions(:string, "Version numbers", required: true)
          end

          example(%{
            default: %{
              version: "1.0.0",
              url: "https://schema.example.com:443/api"
            },
            versions: [
              %{
                version: "1.1.0-dev",
                url: "https://schema.example.com:443/1.1.0-dev/api"
              },
              %{
                version: "1.0.0",
                url: "https://schema.example.com:443/1.0.0/api"
              }
            ]
          })
        end,
      ClassDesc:
        swagger_schema do
          title("Class Descriptor")
          description("Schema class descriptor.")

          properties do
            name(:string, "Class name", required: true)
            caption(:string, "Class caption", required: true)
            description(:string, "Class description", required: true)
            category(:string, "Class category", required: true)
            category_name(:string, "Class category caption", required: true)
            profiles(:array, "Class profiles", items: %PhoenixSwagger.Schema{type: :string})
            uid(:integer, "Class unique identifier", required: true)
          end

          example([
            %{
              caption: "DHCP Activity",
              category: "network",
              category_name: "Network Activity",
              description: "DHCP Activity events report MAC to IP assignment via DHCP.",
              name: "dhcp_activity",
              profiles: [
                "cloud",
                "datetime",
                "host",
                "file_security"
              ],
              uid: 4004
            }
          ])
        end,
      ObjectDesc:
        swagger_schema do
          title("Object Descriptor")
          description("Schema object descriptor.")

          properties do
            name(:string, "Object name", required: true)
            caption(:string, "Object caption", required: true)
            description(:string, "Object description", required: true)
            observable(:integer, "Observable ID")
            profiles(:array, "Object profiles", items: %PhoenixSwagger.Schema{type: :string})
          end

          example([
            %{
              caption: "File",
              description:
                "The file object describes files, folders, links and mounts, including the reputation information, if applicable.",
              name: "file",
              observable: 24,
              profiles: [
                "file_security"
              ]
            }
          ])
        end,
      Event:
        swagger_schema do
          title("Event")
          description("An OCSF formatted event object.")
          type(:object)
        end
    }
  end

  @doc """
  Get the OCSF schema version.
  """
  swagger_path :version do
    get("/api/version")
    summary("Version")
    description("Get OCSF schema version.")
    produces("application/json")
    tag("Schema")
    response(200, "Success", :Version)
  end

  @spec version(Plug.Conn.t(), any) :: Plug.Conn.t()
  def version(conn, _params) do
    version = %{:version => Schema.version()}
    send_json_resp(conn, version)
  end

  @doc """
  Get available OCSF schema versions.
  """
  swagger_path :versions do
    get("/api/versions")
    summary("Versions")
    description("Get available OCSF schema versions.")
    produces("application/json")
    tag("Schema")
    response(200, "Success", :Versions)
  end

  @spec versions(Plug.Conn.t(), any) :: Plug.Conn.t()
  def versions(conn, _params) do
    url = Application.get_env(:schema_server, SchemaWeb.Endpoint)[:url]

    # The :url key is meant to be set for production, but isn't set for local development
    base_url =
      if url == nil do
        "#{conn.scheme}://#{conn.host}:#{conn.port}"
      else
        "#{conn.scheme}://#{Keyword.fetch!(url, :host)}:#{Keyword.fetch!(url, :port)}"
      end

    available_versions =
      Schemas.versions()
      |> Enum.map(fn {version, _} -> version end)

    default_version = %{
      :version => Schema.version(),
      :url => "#{base_url}/#{Schema.version()}/api"
    }

    versions_response =
      case available_versions do
        [] ->
          # If there is no response, we only provide a single schema
          %{:versions => [default_version], :default => default_version}

        [_head | _tail] ->
          available_versions_objects =
            available_versions
            |> Enum.map(fn version ->
              %{:version => version, :url => "#{base_url}/#{version}/api"}
            end)

          %{:versions => available_versions_objects, :default => default_version}
      end

    send_json_resp(conn, versions_response)
  end

  @doc """
  Get the schema data types.
  """
  swagger_path :data_types do
    get("/api/data_types")
    summary("Data types")
    description("Get OCSF schema data types.")
    produces("application/json")
    tag("Objects and Types")
    response(200, "Success")
  end

  @spec data_types(Plug.Conn.t(), any) :: Plug.Conn.t()
  def data_types(conn, _params) do
    send_json_resp(conn, Schema.export_data_types())
  end

  @doc """
  Get the schema extensions.
  """
  swagger_path :extensions do
    get("/api/extensions")
    summary("List extensions")
    description("Get OCSF schema extensions.")
    produces("application/json")
    tag("Schema")
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
  """
  swagger_path :profiles do
    get("/api/profiles")
    summary("List profiles")
    description("Get OCSF schema profiles.")
    produces("application/json")
    tag("Schema")
    response(200, "Success")
  end

  @spec profiles(Plug.Conn.t(), any) :: Plug.Conn.t()
  def profiles(conn, params) do
    profiles =
      Enum.into(get_profiles(params), %{}, fn {k, v} ->
        {k, Schema.delete_links(v)}
      end)

    send_json_resp(conn, profiles)
  end

  @doc """
    Returns the list of profiles.
  """
  @spec get_profiles(map) :: map
  def get_profiles(params) do
    extensions = parse_options(extensions(params))
    Schema.profiles(extensions)
  end

  @doc """
  Get a profile by name.
  get /api/profiles/:name
  get /api/profiles/:extension/:name
  """
  swagger_path :profile do
    get("/api/profiles/{name}")
    summary("Profile")

    description(
      "Get OCSF schema profile by name. The profile name may contain an extension name. For example, \"linux/linux_users\"."
    )

    produces("application/json")
    tag("Schema")

    parameters do
      name(:path, :string, "Profile name", required: true)
    end

    response(200, "Success")
    response(404, "Profile <code>name</code> not found")
  end

  @spec profile(Plug.Conn.t(), map) :: Plug.Conn.t()
  def profile(conn, %{"id" => id} = params) do
    name =
      case params["extension"] do
        nil -> id
        extension -> "#{extension}/#{id}"
      end

    try do
      data = Schema.profiles()

      case Map.get(data, name) do
        nil ->
          send_json_resp(conn, 404, %{error: "Profile #{name} not found"})

        profile ->
          send_json_resp(conn, Schema.delete_links(profile))
      end
    rescue
      e ->
        Logger.error("Unable to get profile: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  @doc """
  Get the schema categories.
  """
  swagger_path :categories do
    get("/api/categories")
    summary("List categories")
    description("Get OCSF schema categories.")
    produces("application/json")
    tag("Categories and Classes")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )
    end

    response(200, "Success")
  end

  @doc """
    Returns the list of categories.
  """
  @spec categories(Plug.Conn.t(), map) :: Plug.Conn.t()
  def categories(conn, params) do
    send_json_resp(conn, categories(params))
  end

  @spec categories(map()) :: map()
  def categories(params) do
    parse_options(extensions(params)) |> Schema.categories()
  end

  @doc """
  Get the classes defined in a given category.
  """
  swagger_path :category do
    get("/api/categories/{name}")
    summary("List category classes")

    description(
      "Get OCSF schema classes defined in the named category. The category name may contain an extension name. For example, \"dev/policy\"."
    )

    produces("application/json")
    tag("Categories and Classes")

    parameters do
      name(:path, :string, "Category name", required: true)

      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )
    end

    response(200, "Success")
    response(404, "Category <code>name</code> not found")
  end

  @spec category(Plug.Conn.t(), map) :: Plug.Conn.t()
  def category(conn, %{"id" => id} = params) do
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

  @spec category_classes(map()) :: map() | nil
  def category_classes(params) do
    name = params["id"]
    extension = extension(params)
    extensions = parse_options(extensions(params))

    Schema.category(extensions, extension, name)
  end

  @doc """
  Get the schema dictionary.
  """
  swagger_path :dictionary do
    get("/api/dictionary")
    summary("Dictionary")
    description("Get OCSF schema dictionary.")
    produces("application/json")
    tag("Dictionary")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )
    end

    response(200, "Success")
  end

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

  @doc """
  Get the schema base event class.
  """
  swagger_path :base_event do
    get("/api/base_event")
    summary("Base event")
    description("Get OCSF schema base event class.")
    produces("application/json")
    tag("Categories and Classes")

    parameters do
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
  end

  @spec base_event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def base_event(conn, params) do
    class(conn, "base_event", params)
  end

  @doc """
  Get an event class by name.
  get /api/classes/:name
  """
  swagger_path :class do
    get("/api/classes/{name}")
    summary("Event class")

    description(
      "Get OCSF schema class by name. The class name may contain an extension name. For example, \"dev/cpu_usage\"."
    )

    produces("application/json")
    tag("Categories and Classes")

    parameters do
      name(:path, :string, "Class name", required: true)
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
    response(404, "Event class <code>name</code> not found")
  end

  @spec class(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def class(conn, %{"id" => id} = params) do
    class(conn, id, params)
  end

  defp class(conn, id, params) do
    extension = extension(params)

    try do
      case Schema.class(extension, id, parse_options(profiles(params))) do
        nil ->
          send_json_resp(conn, 404, %{error: "Event class #{id} not found"})

        data ->
          class = add_objects(data, params)
          send_json_resp(conn, class)
      end
    rescue
      e ->
        Logger.error("Unable to get class: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  @doc """
  Get the schema classes.
  """
  swagger_path :classes do
    get("/api/classes")
    summary("List classes")
    description("Get OCSF schema classes.")
    produces("application/json")
    tag("Categories and Classes")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success", :ClassDesc)
  end

  @spec classes(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def classes(conn, params) do
    classes =
      Enum.map(classes(params), fn {_name, class} ->
        Schema.reduce_class(class)
      end)

    send_json_resp(conn, classes)
  end

  @doc """
    Returns the list of classes.
  """
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

  @doc """
  Get an object by name.
  get /api/objects/:name
  get /api/objects/:extension/:name
  """
  swagger_path :object do
    get("/api/objects/{name}")
    summary("Object")

    description(
      "Get OCSF schema object by name. The object name may contain an extension name. For example, \"dev/os_service\"."
    )

    produces("application/json")
    tag("Objects and Types")

    parameters do
      name(:path, :string, "Object name", required: true)

      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
    response(404, "Object <code>name</code> not found")
  end

  @spec object(Plug.Conn.t(), map) :: Plug.Conn.t()
  def object(conn, %{"id" => id} = params) do
    try do
      case object(params) do
        nil ->
          send_json_resp(conn, 404, %{error: "Object #{id} not found"})

        data ->
          send_json_resp(conn, add_objects(data, params))
      end
    rescue
      e ->
        Logger.error("Unable to get object: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  @doc """
  Get the schema objects.
  """
  swagger_path :objects do
    get("/api/objects")
    summary("List objects")
    description("Get OCSF schema objects.")
    produces("application/json")
    tag("Objects and Types")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )
    end

    response(200, "Success", :ObjectDesc)
  end

  @spec objects(Plug.Conn.t(), map) :: Plug.Conn.t()
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

  @doc """
  Export the OCSF schema definitions.
  """
  swagger_path :export_schema do
    get("/export/schema")
    summary("Export schema")
    description("Get OCSF schema definitions, including data types, objects, and classes.")
    produces("application/json")
    tag("Schema Export")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
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
  """
  swagger_path :export_classes do
    get("/export/classes")
    summary("Export classes")
    description("Get OCSF schema classes.")
    produces("application/json")
    tag("Schema Export")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
  end

  def export_classes(conn, params) do
    profiles = parse_options(profiles(params))
    classes = parse_options(extensions(params)) |> Schema.export_classes(profiles)
    send_json_resp(conn, classes)
  end

  @doc """
  Export the OCSF base event class.
  """
  swagger_path :export_base_event do
    get("/export/base_event")
    summary("Export base event class")
    description("Get OCSF schema base event class.")
    produces("application/json")
    tag("Schema Export")

    parameters do
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
  end

  def export_base_event(conn, params) do
    profiles = parse_options(profiles(params))
    base_event = Schema.export_base_event(profiles)

    send_json_resp(conn, base_event)
  end

  @doc """
  Export the OCSF schema objects.
  """
  swagger_path :export_objects do
    get("/export/objects")
    summary("Export objects")
    description("Get OCSF schema objects.")
    produces("application/json")
    tag("Schema Export")

    parameters do
      extensions(:query, :array, "Related extensions to include in response.",
        items: [type: :string]
      )

      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
  end

  def export_objects(conn, params) do
    profiles = parse_options(profiles(params))
    objects = parse_options(extensions(params)) |> Schema.export_objects(profiles)
    send_json_resp(conn, objects)
  end

  # -----------------
  # JSON Schema API's
  # -----------------

  @doc """
  Get JSON schema definitions for a given event class.
  get /schema/classes/:name
  """
  swagger_path :json_class do
    get("/schema/classes/{name}")
    summary("Event class")

    description(
      "Get OCSF schema class by name, using JSON schema Draft-07 format (see http://json-schema.org). The class name may contain an extension name. For example, \"dev/cpu_usage\"."
    )

    produces("application/json")
    tag("JSON Schema")

    parameters do
      name(:path, :string, "Class name", required: true)
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
      package_name(:query, :string, "Java package name")
    end

    response(200, "Success")
    response(404, "Event class <code>name</code> not found")
  end

  @spec json_class(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def json_class(conn, %{"id" => id} = params) do
    options = Map.get(params, "package_name") |> parse_java_package()

    try do
      case class_ex(id, params) do
        nil ->
          send_json_resp(conn, 404, %{error: "Event class #{id} not found"})

        data ->
          class = Schema.JsonSchema.encode(data, options)
          send_json_resp(conn, class)
      end
    rescue
      e ->
        Logger.error("Unable to get class: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  def class_ex(id, params) do
    extension = extension(params)
    Schema.class_ex(extension, id, parse_options(profiles(params)))
  end

  @doc """
  Get JSON schema definitions for a given event object.
  get /schema/classes/:name
  """
  swagger_path :json_object do
    get("/schema/objects/{name}")
    summary("Object")

    description(
      "Get OCSF object by name, using JSON schema Draft-07 format (see http://json-schema.org). The object name may contain an extension name. For example, \"dev/printer\"."
    )

    produces("application/json")
    tag("JSON Schema")

    parameters do
      name(:path, :string, "Object name", required: true)
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
      package_name(:query, :string, "Java package name")
    end

    response(200, "Success")
    response(404, "Object <code>name</code> not found")
  end

  @spec json_object(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def json_object(conn, %{"id" => id} = params) do
    options = Map.get(params, "package_name") |> parse_java_package()

    try do
      case object_ex(id, params) do
        nil ->
          send_json_resp(conn, 404, %{error: "Object #{id} not found"})

        data ->
          object = Schema.JsonSchema.encode(data, options)
          send_json_resp(conn, object)
      end
    rescue
      e ->
        Logger.error("Unable to get object: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  def object_ex(id, params) do
    profiles = parse_options(profiles(params))
    extension = extension(params)
    extensions = parse_options(extensions(params))

    Schema.object_ex(extensions, extension, id, profiles)
  end

  # ---------------------------------------------
  # Enrichment, validation, and translation API's
  # ---------------------------------------------

  @doc """
  Enrich event data by adding type_uid, enumerated text, and observables.
  A single event is encoded as a JSON object and multiple events are encoded as JSON array of objects.
  """
  swagger_path :enrich do
    post("/api/enrich")
    summary("Enrich Event")

    description("""
    The purpose of this API is to enrich the provided event data with <code>type_uid</code>, enumerated text, and <code>observables</code> array.
    Each event is represented as a JSON object, while multiple events are encoded as a JSON array of objects.
    """)

    produces("application/json")
    tag("Tools")

    parameters do
      _enum_text(
        :query,
        :boolean,
        """
        Enhance the event data by adding the enumerated text values.<br/>

        |Value|Example|
        |-----|-------|
        |true|Untranslated:<br/><code>{"category_uid":0,"class_uid":0,"activity_id": 0,"severity_id": 5,"status": "Something else","status_id": 99,"time": 1689125893360905}</code><br/><br/>Translated:<br/><code>{"activity_name": "Unknown", "activity_id": 0, "category_name": "Uncategorized", "category_uid": 0, "class_name": "Base Event", "class_uid": 0, "severity": "Critical", "severity_id": 5, "status": "Something else", "status_id": 99, "time": 1689125893360905, "type_name": "Base Event: Unknown", "type_uid": 0}</code>|
        """,
        default: false
      )

      _observables(
        :query,
        :boolean,
        """
        <strong>TODO</strong>: Enhance the event data by adding the observables associated with the event.
        """,
        default: false
      )

      data(:body, PhoenixSwagger.Schema.ref(:Event), "The event data to be enriched.",
        required: true
      )
    end

    response(200, "Success")
  end

  @spec enrich(Plug.Conn.t(), map) :: Plug.Conn.t()
  def enrich(conn, data) do
    {enum_text, data} = Map.pop(data, @enum_text)
    {observables, data} = Map.pop(data, @observables)

    result =
      case data["_json"] do
        # Enrich a single events
        nil ->
          Schema.enrich(data, enum_text, observables)

        # Enrich a list of events
        list when is_list(list) ->
          Enum.map(list, &Task.async(fn -> Schema.enrich(&1, enum_text, observables) end))
          |> Enum.map(&Task.await/1)

        # something other than json data
        other ->
          %{:error => "The data does not look like an event", :data => other}
      end

    send_json_resp(conn, result)
  end

  @doc """
  Translate event data. A single event is encoded as a JSON object and multiple events are encoded as JSON array of objects.
  """
  swagger_path :translate do
    post("/api/translate")
    summary("Translate Event")

    description("""
    The purpose of this API is to translate the provided event data using the OCSF schema.
    Each event is represented as a JSON object, while multiple events are encoded as a JSON array of objects.
    """)

    produces("application/json")
    tag("Tools")

    parameters do
      _mode(
        :query,
        :number,
        """
        Controls how attribute names and enumerated values are translated.<br/>
        The format is _mode=[1|2|3]. The default mode is `1` -- translate enumerated values.

        |Value|Description|Example|
        |-----|-----------|-------|
        |1|Translate only the enumerated values|Untranslated:<br/><code>{"class_uid": 1000}</code><br/><br/>Translated:<br/><code>{"class_name": File Activity", "class_uid": 1000}</code>|
        |2|Translate enumerated values and attribute names|Untranslated:<br/><code>{"class_uid": 1000}</code><br/><br/>Translated:<br/><code>{"Class": File Activity", "Class ID": 1000}</code>|
        |3|Verbose translation|Untranslated:<br/><code>{"class_uid": 1000}</code><br/><br/>Translated:<br/><code>{"class_uid": {"caption": "File Activity","name": "Class ID","type": "integer_t","value": 1000}}</code>|
        """,
        default: 1
      )

      _spaces(
        :query,
        :string,
        """
          Controls how spaces in the translated attribute names are handled.<br/>
          By default, the translated attribute names may contain spaces (for example, Event Time). You can remove the spaces or replace the spaces with another string. For example, if you want to forward to a database that does not support spaces.<br/>
          The format is _spaces=[&lt;empty&gt;|string].

          |Value|Description|Example|
          |-----|-----------|-------|
          |&lt;empty&gt;|The spaces in the translated names are removed.|Untranslated:<br/><code>{"class_uid": 1000}</code><br/><br/>Translated:<br/><code>{"ClassID": File Activity"}</code>|
          |string|The spaces in the translated names are replaced with the given string.|For example, the string is an underscore (_).<br/>Untranslated:<br/><code>{"class_uid": 1000}</code><br/><br/>Translated:<br/><code>{"Class_ID": File Activity"}</code>|
        """,
        allowEmptyValue: true
      )

      data(:body, PhoenixSwagger.Schema.ref(:Event), "The event data to be translated",
        required: true
      )
    end

    response(200, "Success")
  end

  @spec translate(Plug.Conn.t(), map) :: Plug.Conn.t()
  def translate(conn, data) do
    options = [spaces: data[@spaces], verbose: verbose(data[@verbose])]

    result =
      case data["_json"] do
        # Translate a single events
        nil ->
          Map.delete(data, @verbose)
          |> Map.delete(@spaces)
          |> Schema.Translator.translate(options)

        # Translate a list of events
        list when is_list(list) ->
          Enum.map(list, fn data -> Schema.Translator.translate(data, options) end)

        # some other json data
        other ->
          %{:error => "The data does not look like an event", "data" => other}
      end

    send_json_resp(conn, result)
  end

  @doc """
    Validate event data.
    A single event is encoded as a JSON object and multiple events are encoded as JSON array of object.
    post /api/validate
  """
  swagger_path :validate do
    post("/api/validate")
    summary("Validate Event")

    description("""
    The primary objective of this API is to validate the provided event data against the OCSF schema.
    Each event is represented as a JSON object, while multiple events are encoded as a JSON array of objects.
    """)

    produces("application/json")
    tag("Tools")

    parameters do
      data(:body, PhoenixSwagger.Schema.ref(:Event), "The event data to be validated",
        required: true
      )
    end

    response(200, "Success")
  end

  @spec validate(Plug.Conn.t(), map) :: Plug.Conn.t()
  def validate(conn, data) do
    result =
      case data["_json"] do
        # Validate a single events
        nil ->
          Schema.Inspector.validate(data)

        # Validate a list of events
        list when is_list(list) ->
          Enum.map(list, &Task.async(fn -> Schema.Inspector.validate(&1) end))
          |> Enum.map(&Task.await/1)

        # some other json data
        other ->
          %{:error => "The data does not look like an event", "data" => other}
      end

    send_json_resp(conn, result)
  end

  # --------------------------
  # Request sample data API's
  # --------------------------

  @doc """
  Returns randomly generated event sample data for the base event class.
  """
  swagger_path :sample_event do
    get("/sample/base_event")
    summary("Base event sample data")
    description("This API returns randomly generated sample data for the base event class.")
    produces("application/json")
    tag("Sample Data")

    parameters do
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
  end

  @spec sample_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_event(conn, params) do
    sample_class(conn, "base_event", params)
  end

  @doc """
  Returns randomly generated event sample data for the given name.
  get /sample/classes/:name
  get /sample/classes/:extension/:name
  """
  swagger_path :sample_class do
    get("/sample/classes/{name}")
    summary("Event sample data")

    description(
      "This API returns randomly generated sample data for the given event class name. The class name may contain an extension name. For example, \"dev/cpu_usage\"."
    )

    produces("application/json")
    tag("Sample Data")

    parameters do
      name(:path, :string, "Class name", required: true)
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
    response(404, "Event class <code>name</code> not found")
  end

  @spec sample_class(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_class(conn, %{"id" => id} = params) do
    sample_class(conn, id, params)
  end

  defp sample_class(conn, id, options) do
    extension = extension(options)
    profiles = profiles(options) |> parse_options()

    try do
      case Schema.class(extension, id) do
        nil ->
          send_json_resp(conn, 404, %{error: "Event class #{id} not found"})

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

  @doc """
  Returns randomly generated object sample data for the given name.
  get /sample/objects/:name
  get /sample/objects/:extension/:name
  """
  swagger_path :sample_object do
    get("/sample/objects/{name}")
    summary("Object sample data")

    description(
      "This API returns randomly generated sample data for the given object name. The object name may contain an extension name. For example, \"dev/os_service\"."
    )

    produces("application/json")
    tag("Sample Data")

    parameters do
      name(:path, :string, "Object name", required: true)
      profiles(:query, :array, "Related profiles to include in response.", items: [type: :string])
    end

    response(200, "Success")
    response(404, "Object <code>name</code> not found")
  end

  @spec sample_object(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_object(conn, %{"id" => id} = options) do
    extension = extension(options)
    profiles = profiles(options) |> parse_options()

    try do
      case Schema.object(extension, id) do
        nil ->
          send_json_resp(conn, 404, %{error: "Object #{id} not found"})

        data ->
          send_json_resp(conn, Schema.generate_object(data, profiles))
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
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-headers", "content-type")
    |> put_resp_header("access-control-allow-methods", "POST, GET, OPTIONS")
    |> send_resp(error, Jason.encode!(data))
  end

  defp send_json_resp(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-headers", "content-type")
    |> put_resp_header("access-control-allow-methods", "POST, GET, OPTIONS")
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
        type = field[:object_type] |> String.to_existing_atom()

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

  defp verbose(_), do: 1

  defp profiles(params), do: params["profiles"]
  defp extension(params), do: params["extension"]
  defp extensions(params), do: params["extensions"]

  defp parse_options(nil), do: nil
  defp parse_options(""), do: MapSet.new()

  defp parse_options(options) do
    options
    |> String.split(",")
    |> Enum.map(fn s -> String.trim(s) end)
    |> MapSet.new()
  end

  defp parse_java_package(nil), do: []
  defp parse_java_package(""), do: []
  defp parse_java_package(name), do: [package_name: name]
end
