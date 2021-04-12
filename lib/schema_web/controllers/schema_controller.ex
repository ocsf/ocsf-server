defmodule SchemaWeb.SchemaController do
  @moduledoc """
  The Event Schema API.
  """
  use SchemaWeb, :controller

  require Logger

  @verbose "_mode"
  @spaces "_spaces"

  @doc """
  Renders categories or the classes in a given category.
  """
  @spec categories(Plug.Conn.t(), map) :: Plug.Conn.t()
  def categories(conn, %{"id" => id}) do
    try do
      case Schema.categories(Schema.to_uid(id)) do
        nil ->
          response(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          response(conn, remove_links(:classes, data))
      end
    rescue
      e ->
        Logger.error("Unable to classes for category: #{id}. Error: #{inspect(e)}")
        response(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  def categories(conn, _params) do
    response(conn, Schema.categories())
  end

  @doc """
  Renders the attribute dictionary.
  """
  @spec dictionary(Plug.Conn.t(), any) :: Plug.Conn.t()
  def dictionary(conn, _params) do
    response(conn, remove_links(:attributes, Schema.dictionary()))
  end

  @doc """
  Renders the base event attributes.
  """
  @spec base_event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def base_event(conn, _params) do
    response(conn, remove_links(:attributes, Schema.classes(:event)))
  end

  @spec event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def event(conn, _params) do
    response(conn, Schema.event(:event))
  end

  @doc """
  Renders event classes.
  """
  @spec classes(Plug.Conn.t(), any) :: Plug.Conn.t()
  def classes(conn, %{"id" => id}) do
    try do
      case Schema.classes(Schema.to_uid(id)) do
        nil ->
          response(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          response(conn, remove_links(:attributes, data))
      end
    rescue
      e ->
        Logger.error("Unable to get class: #{id}. Error: #{inspect(e)}")
        response(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  def classes(conn, _params) do
    response(conn, Schema.classes())
  end

  def class(conn, %{"id" => id} = options) do
    try do
      case Schema.classes(Schema.to_uid(id)) do
        nil ->
          response(conn, 404, %{error: "Not Found: #{id}"})

        class ->
          event =
            case Map.get(options, @verbose) do
              nil ->
                Schema.event(class)

              verbose ->
                Schema.event(class)
                |> Schema.Translator.translate(verbose: verbose(verbose))
            end

          response(conn, event)
      end
    rescue
      e ->
        Logger.error("Unable to generate sample for class: #{id}. Error: #{inspect(e)}")
        response(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  @doc """
  Renders objects.
  """
  @spec objects(Plug.Conn.t(), map) :: Plug.Conn.t()
  def objects(conn, %{"id" => id}) do
    try do
      case Schema.objects(Schema.to_uid(id)) do
        nil ->
          response(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          response(conn, remove_links(:attributes, data))
      end
    rescue
      e ->
        Logger.error("Unable to get object: #{id}. Error: #{inspect(e)}")
        response(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  def objects(conn, _params) do
    response(conn, Schema.objects())
  end

  def object(conn, %{"id" => id}) do
    try do
      case Schema.objects(Schema.to_uid(id)) do
        nil ->
          response(conn, 404, %{error: "Not Found: #{id}"})

        data ->
          response(conn, Schema.generate(data))
      end
    rescue
      e ->
        Logger.error("Unable to generate sample for object: #{id}. Error: #{inspect(e)}")
        response(conn, 500, %{error: "Error: #{e[:message]}"})
    end
  end

  @spec translate(Plug.Conn.t(), map) :: Plug.Conn.t()
  def translate(conn, data) do
    options =
      [verbose: verbose(data[@verbose])]
      |> Keyword.put(:spaces, data[@spaces])

    case data["_json"] do
      nil ->
        # Translate a single events
        data =
          Map.delete(data, @verbose)
          |> Map.delete(@spaces)
          |> Schema.Translator.translate(options)

        response(conn, data)

      list when is_list(list) ->
        # Translate a list of events
        translated = Enum.map(list, fn data -> Schema.Translator.translate(data, options) end)
        response(conn, translated)

      other ->
        # some other json data
        response(conn, other)
    end
  end

  defp response(conn, error, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(error, Jason.encode!(data))
  end

  defp response(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  defp remove_links(key, data) do
    case data[key] do
      nil ->
        data

      attributes ->
        updated = Enum.map(attributes, fn {k, v} -> %{k => Map.delete(v, :_links)} end)
        Map.put(data, key, updated)
    end
  end

  defp verbose(nil), do: 0

  defp verbose(option) when is_binary(option) do
    case Integer.parse(option) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp verbose(_), do: 0
end
