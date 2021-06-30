defmodule SchemaWeb.SchemaController do
  @moduledoc """
  The Event Schema API.
  """
  use SchemaWeb, :controller

  require Logger

  @verbose "_mode"
  @spaces "_spaces"

  # -------------------
  # Event Schema API's
  # -------------------

  # {
  # @api {get} /api/categories/:name Request Category
  # @apiName Category
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} name Category name
  # }
  @doc """
  Renders categories or the classes in a given category.
  """
  @spec categories(Plug.Conn.t(), map) :: Plug.Conn.t()
  def categories(conn, %{"id" => id}) do
    try do
      case Schema.categories(Schema.to_uid(id)) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          send_json_resp(conn, remove_links(data, :classes))
      end
    rescue
      e ->
        Logger.error("Unable to classes for category: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /api/categories Request Categories
  # @apiName Categories
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  def categories(conn, _params) do
    send_json_resp(conn, Schema.categories())
  end

  # {
  # @api {get} /api/dictionary Request Dictionary
  # @apiName Dictionary
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  @doc """
  Renders the attribute dictionary.
  """
  @spec dictionary(Plug.Conn.t(), any) :: Plug.Conn.t()
  def dictionary(conn, _params) do
    send_json_resp(conn, remove_links(Schema.dictionary(), :attributes))
  end

  # {
  # @api {get} /api/base_event Request Base Event
  # @apiName Base Event
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  @doc """
  Renders the base event attributes.
  """
  @spec base_event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def base_event(conn, _params) do
    send_json_resp(conn, remove_links(Schema.classes(:event), :attributes))
  end

  # {
  # @api {get} /api/classes/:type Request Class
  # @apiName Class
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} type Event class type name, for example: `mem_usage`
  # }
  @doc """
  Renders event classes.
  """
  @spec classes(Plug.Conn.t(), any) :: Plug.Conn.t()
  def classes(conn, %{"id" => id}) do
    try do
      case Schema.classes(Schema.to_uid(id)) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          send_json_resp(conn, remove_links(data))
      end
    rescue
      e ->
        Logger.error("Unable to get class: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /api/classes Request all Classes
  # @apiName Class
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  def classes(conn, _params) do
    classes =
      Enum.map(Schema.classes(), fn {_name, class} ->
        Map.delete(class, :see_also) |> Map.delete(:attributes)
      end)

    send_json_resp(conn, classes)
  end

  # {
  # @api {get} /api/objects/:type Request Object
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
  def objects(conn, %{"id" => id}) do
    try do
      case Schema.objects(Schema.to_uid(id)) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          objects = remove_links(data)
          send_json_resp(conn, objects)
      end
    rescue
      e ->
        Logger.error("Unable to get object: #{id}. Error: #{inspect(e)}")
        send_json_resp(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  # {
  # @api {get} /api/objects Request all Objects
  # @apiName Objects
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  def objects(conn, _params) do
    objects =
      Enum.map(Schema.objects(), fn {_name, map} ->
        Map.delete(map, :_links)
      end)

    send_json_resp(conn, objects)
  end

  # {
  # @api {get} /api/schema Request the schema hierarchy
  # @apiName Schema
  # @apiGroup Schema
  # @apiVersion 1.0.0
  # @apiPermission none
  # }
  @spec schema(Plug.Conn.t(), any) :: Plug.Conn.t()
  def schema(conn, _params) do
    send_json_resp(conn, Schema.hierarchy())
  end

  # ---------------------------------
  # Validation and translation API's
  # ---------------------------------

  # {
  # @api {post} /api/translate?_mode=:mode Translate Event Data
  # @apiName Translate
  # @apiGroup Data
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {Number=1,2,3} _mode  Controls how the attribute names and enumerated values are translated
  # @apiParam {String} _spaces  Controls how the spaces in the translated attribute names are handled
  # @apiParam {JSON} event  The event to be translated as a JSON object
  #
  # @apiParamExample {json} Request-Example:
  #     {
  #       "class_id": 100,
  #       "disposition_id": 1,
  #       "severity_id": 1,
  #       "message": "This is an important message"
  #     }
  #
  # @apiSuccessExample {json} Success-Response:
  #     {
  #       "class_id": "Entity Audit",
  #       "message": "This is an important message",
  #       "disposition_id": "Created",
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
  # @api {post} /api/validate Validate Event Data
  # @apiName Validate
  # @apiGroup Data
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {JSON} event  The event or events to be translated. A single event is encoded as a JSON object and multiple events are encoded as JSON array of object.
  #
  # @apiSuccess {JSON} An empty JSON object
  #      HTTP/1.1 200 OK
  #      {}
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

  # {
  # @api {get} /sample/base_event Request Base Event data
  # @apiName Base Event Sample
  # @apiGroup Sample
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiSuccess {JSON} The randomly generated sample data
  # }
  @doc """
  Returns a base event sample.
  """
  @spec sample_event(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_event(conn, _params) do
    send_json_resp(conn, Schema.event(:event))
  end

  # {
  # @api {get} /sample/classes/:name Request Event data
  # @apiName Event Sample
  # @apiGroup Sample
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} name Event class name
  # @apiSuccess {JSON} The randomly generated sample data
  # }
  @doc """
  Returns an event sample for the given name.
  """
  @spec sample_class(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_class(conn, %{"id" => id} = options) do
    try do
      case Schema.classes(Schema.to_uid(id)) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

        class ->
          event =
            case Map.get(options, @verbose) do
              nil ->
                Schema.event(class)

              verbose ->
                Schema.event(class)
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
  # @api {get} /sample/objects/:name Request Object data
  # @apiName Object Sample
  # @apiGroup Sample
  # @apiVersion 1.0.0
  # @apiPermission none
  # @apiParam {String} name Object name
  # @apiSuccess {JSON} The randomly generated sample data
  # }
  @doc """
  Returns an object sample data for the given name.
  """
  @spec sample_object(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sample_object(conn, %{"id" => id}) do
    try do
      case Schema.objects(Schema.to_uid(id)) do
        nil ->
          send_json_resp(conn, 404, %{error: "Not Found: #{id}"})

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
    |> Map.delete(:_links)
    |> Map.delete(:see_also)
    |> remove_links(:attributes)
  end

  defp remove_links(data, key) do
    case data[key] do
      nil ->
        data

      attributes ->
        updated = Enum.map(attributes, fn {k, v} -> %{k => Map.delete(v, :_links)} end)
        Map.put(data, key, updated)
    end
  end

  defp verbose(option) when is_binary(option) do
    case Integer.parse(option) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp verbose(_), do: 0
end
