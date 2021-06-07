defmodule SchemaWeb.PageController do
  @moduledoc """
  The schema server web pages
  """
  use SchemaWeb, :controller

  @spec guidelines(Plug.Conn.t(), any) :: Plug.Conn.t()
  def guidelines(conn, _params) do
    render(conn, "guidelines.html")
  end

  def view(conn, _params) do
    render(conn, "h.html")
  end

  @doc """
  Renders categories or the classes in a given category.
  """
  @spec categories(Plug.Conn.t(), map) :: Plug.Conn.t()
  def categories(conn, %{"id" => id}) do
    try do
      case Schema.categories(Schema.to_uid(id)) do
        nil ->
          send_resp(conn, 404, "Not Found: #{id}")

        data ->
          classes = sort_by_type_id(data.classes)
          render(conn, "category.html", data: Map.put(data, :classes, classes))
      end
    rescue
      e -> send_resp(conn, 400, "Bad Request: #{e[:message]}")
    end
  end

  def categories(conn, _params) do
    data = Schema.categories() |> sort_attributes
    render(conn, "index.html", data: data)
  end

  @doc """
  Renders the data types.
  """
  @spec data_types(Plug.Conn.t(), any) :: Plug.Conn.t()
  def data_types(conn, _params) do
    data = Schema.dictionary()[:types] |> sort_attributes

    render(conn, "data_types.html", data: data)
  end

  @doc """
  Renders the attribute dictionary.
  """
  @spec dictionary(Plug.Conn.t(), any) :: Plug.Conn.t()
  def dictionary(conn, _params) do
    data = Schema.dictionary() |> sort_attributes

    render(conn, "dictionary.html", data: data)
  end

  @doc """
  Renders the base event attributes.
  """
  @spec base_event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def base_event(conn, _params) do
    data = Schema.classes(:event) |> sort_attributes

    render(conn, "class.html", data: data)
  end

  @doc """
  Renders event classes.
  """
  @spec classes(Plug.Conn.t(), any) :: Plug.Conn.t()
  def classes(conn, %{"id" => id}) do
    try do
      case Schema.classes(Schema.to_uid(id)) do
        nil ->
          send_resp(conn, 404, "Not Found: #{id}")

        data ->
          render(conn, "class.html", data: sort_attributes(data))
      end
    rescue
      e -> send_resp(conn, 400, "Bad Request: #{e[:message]}")
    end
  end

  def classes(conn, _params) do
    data = Schema.classes() |> sort_by_type_id
    render(conn, "classes.html", data: data)
  end

  @doc """
  Renders objects.
  """
  @spec objects(Plug.Conn.t(), map) :: Plug.Conn.t()
  def objects(conn, %{"id" => id}) do
    try do
      case Schema.objects(Schema.to_uid(id)) do
        nil ->
          send_resp(conn, 404, "Not Found: #{id}")

        data ->
          render(conn, "class.html", data: sort_attributes(data))
      end
    rescue
      e -> send_resp(conn, 400, "Bad Request: #{e[:message]}")
    end
  end

  def objects(conn, _params) do
    data = Schema.objects() |> sort_by_name
    render(conn, "objects.html", data: data)
  end

  defp sort_attributes(map) do
    Map.put(map, :attributes, sort_by_name(map.attributes))
  end

  defp sort_by_name(map) do
    Enum.sort(map, fn {_, v1}, {_, v2} -> v1.name <= v2.name end)
  end

  defp sort_by_type_id(map) do
    Enum.sort(map, fn {_, v1}, {_, v2} -> v1.uid <= v2.uid end)
  end
end
