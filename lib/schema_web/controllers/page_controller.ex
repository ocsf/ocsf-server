# Copyright 2021 Splunk Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule SchemaWeb.PageController do
  @moduledoc """
  The schema server web pages
  """
  use SchemaWeb, :controller

  @spec guidelines(Plug.Conn.t(), any) :: Plug.Conn.t()
  def guidelines(conn, _params) do
    render(conn, "guidelines.html")
  end

  def schema(conn, _params) do
    render(conn, "schema_map.html")
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
          classes = sort_by_name(data.classes)
          render(conn, "category.html", data: Map.put(data, :classes, classes))
      end
    rescue
      e -> send_resp(conn, 400, "Bad Request: #{e[:message]}")
    end
  end

  def categories(conn, _params) do
    data = Schema.categories() |> sort_attributes(:id)
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
    data = Schema.classes(:base_event)
    render(conn, "class.html", data: sort_attributes(data))
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
    data = Schema.classes() |> sort_by_name()
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
          render(conn, "object.html", data: sort_attributes(data))
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
    sort_attributes(map, :name)
  end

  def sort_attributes(map, key) do
    Map.update!(map, :attributes, &sort_by(&1, key))
  end

  def sort_by_name(map) do
    sort_by(map, :name)
  end

  def sort_by(map, key) do
    Enum.sort(map, fn {_, v1}, {_, v2} -> v1[key] <= v2[key] end)
  end
end
