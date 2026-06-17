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

  alias SchemaWeb.SchemaController

  @spec categories(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def categories(conn, params) do
    data =
      Map.put_new(params, "extensions", "")
      |> SchemaController.categories()
      |> sort_attributes(:uid)
      |> sort_classes()

    render(conn, "index.html",
      extensions: Schema.extensions(),
      profiles: get_profiles(params),
      data: data
    )
  end

  @spec category_by_id(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def category_by_id(conn, params) do
    params = Map.put_new(params, "extensions", "")

    case SchemaController.category_classes(params) do
      nil ->
        send_resp(conn, 404, "Not Found: #{SchemaController.params_to_uid(params)}")

      data ->
        classes = sort_by(data[:classes], :uid)

        render(conn, "category.html",
          extensions: Schema.extensions(),
          profiles: get_profiles(params),
          data: Map.put(data, :classes, classes)
        )
    end
  end

  @spec profiles(Plug.Conn.t(), map) :: Plug.Conn.t()
  def profiles(conn, params) do
    params = Map.put_new(params, "extensions", "")
    profiles = get_profiles(params)
    sorted_profiles = sort_by_descoped_key(profiles)

    render(conn, "profiles.html",
      extensions: Schema.extensions(),
      profiles: profiles,
      data: sorted_profiles
    )
  end

  @spec profile_by_id(Plug.Conn.t(), map) :: Plug.Conn.t()
  def profile_by_id(conn, params) do
    id = SchemaController.params_to_uid(params)

    profiles = get_profiles(params)

    case profiles[id] do
      nil ->
        send_resp(conn, 404, "Not Found: #{id}")

      profile ->
        render(conn, "profile.html",
          schema: Schema.schema(),
          extensions: Schema.extensions(),
          profiles: profiles,
          data: sort_attributes_by_key(profile)
        )
    end
  end

  @spec classes(Plug.Conn.t(), any) :: Plug.Conn.t()
  def classes(conn, params) do
    data =
      Map.put_new(params, "extensions", "")
      |> SchemaController.classes()
      |> sort_by(:uid)

    render(conn, "classes.html",
      extensions: Schema.extensions(),
      profiles: get_profiles(params),
      data: data
    )
  end

  @spec class_by_id(Plug.Conn.t(), any) :: Plug.Conn.t()
  def class_by_id(conn, params) do
    schema = Schema.schema()
    id = SchemaController.params_to_uid(params)
    profiles = parse_profiles_from_params(params)

    case Schema.class_filter_profiles(schema, id, profiles) do
      nil ->
        send_resp(conn, 404, "Not Found: #{id}")

      data ->
        render(conn, "class.html",
          schema: schema,
          extensions: schema[:extensions],
          profiles: get_profiles(params),
          data: sort_attributes_by_key(data)
        )
    end
  end


  @doc """
  Redirects from the older /base_event URL to /classes/base_event.
  """
  @spec base_event(Plug.Conn.t(), any) :: Plug.Conn.t()
  def base_event(conn, _params) do
    redirect(conn, to: "/classes/base_event")
  end

  @spec objects(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def objects(conn, params) do
    params = Map.put_new(params, "extensions", "")

    data =
      SchemaController.parse_options(SchemaController.extensions(params))
      |> Schema.objects_filter_extensions()
      |> sort_by_descoped_key()

    render(conn, "objects.html",
      schema: Schema.schema(),
      extensions: Schema.extensions(),
      profiles: get_profiles(params),
      data: data
    )
  end

  @spec object_by_id(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def object_by_id(conn, params) do
    schema = Schema.schema()
    id = SchemaController.params_to_uid(params)
    profiles = parse_profiles_from_params(params)
    extensions = SchemaController.parse_options(SchemaController.extensions(params))

    case Schema.object_filter_extensions_profiles(schema, id, extensions, profiles) do
      nil ->
        send_resp(conn, 404, "Not Found: #{id}")

      data ->
        render(conn, "object.html",
          schema: schema,
          extensions: schema[:extensions],
          profiles: get_profiles(params),
          data: sort_attributes_by_key(data)
        )
    end
  end


  @spec dictionary(Plug.Conn.t(), any) :: Plug.Conn.t()
  def dictionary(conn, params) do
    params = Map.put_new(params, "extensions", "")
    schema = Schema.schema()

    data =
      SchemaController.parse_options(SchemaController.extensions(params))
      |> Schema.dictionary_filter_extensions(schema)
      |> sort_attributes_by_descoped_key()

    render(conn, "dictionary.html",
      schema: schema,
      extensions: schema[:extensions],
      profiles: get_profiles(params),
      data: data
    )
  end

  @spec data_types(Plug.Conn.t(), any) :: Plug.Conn.t()
  def data_types(conn, params) do
    data = Schema.data_types() |> sort_attributes_by_descoped_key()

    render(conn, "data_types.html",
      schema: Schema.schema(),
      extensions: Schema.extensions(),
      profiles: get_profiles(params),
      data: data
    )
  end

  @spec visualizer(Plug.Conn.t(), any) :: Plug.Conn.t()
  def visualizer(conn, params) do
    cond do
      params["class"] ->
        id = String.to_atom(params["class"])
        case Schema.SingleRepo.clean_classes()[id] do
          nil ->
            send_resp(conn, 404, "Not Found: #{params["class"]}")

          class ->
            render(conn, "visualizer.html",
              extensions: Schema.extensions(),
              profiles: get_profiles(params),
              scope_data: Map.put(class, :scope_type, :class)
            )
        end

      params["object"] ->
        id = String.to_atom(params["object"])
        case Schema.SingleRepo.clean_objects()[id] do
          nil ->
            send_resp(conn, 404, "Not Found: #{params["object"]}")

          obj ->
            render(conn, "visualizer.html",
              extensions: Schema.extensions(),
              profiles: get_profiles(params),
              scope_data: Map.put(obj, :scope_type, :object)
            )
        end

      params["category"] ->
        id = String.to_atom(params["category"])
        case Schema.SingleRepo.categories()[:attributes][id] do
          nil ->
            send_resp(conn, 404, "Not Found: #{params["category"]}")

          cat ->
            scope_data = cat
              |> Map.put(:scope_type, :category)
              |> Map.put_new(:name, params["category"])

            render(conn, "visualizer.html",
              extensions: Schema.extensions(),
              profiles: get_profiles(params),
              scope_data: scope_data
            )
        end

      true ->
        redirect(conn, to: Routes.static_path(conn, "/classes"))
    end
  end

  defp sort_classes(categories) do
    Map.update!(categories, :attributes, fn list ->
      Enum.map(list, fn {name, category} ->
        {name, Map.update!(category, :classes, &sort_by(&1, :uid))}
      end)
    end)
  end

  defp sort_attributes(map, key) do
    Map.update!(map, :attributes, &sort_by(&1, key))
  end

  defp sort_by(map, key) do
    Enum.sort(map, fn {_, v1}, {_, v2} -> v1[key] <= v2[key] end)
  end

  defp sort_attributes_by_key(map) do
    Map.update!(map, :attributes, &sort_by_key/1)
  end

  defp sort_attributes_by_descoped_key(map) do
    Map.update!(map, :attributes, &sort_by_descoped_key/1)
  end

  defp sort_by_key(map) do
    Enum.sort(map, fn {k1, _}, {k2, _} ->
      Atom.to_string(k1) <= Atom.to_string(k2)
    end)
  end

  defp sort_by_descoped_key(map) do
    Enum.sort(map, fn {k1, v1}, {k2, v2} ->
      descoped_k1 = Schema.Utils.descope(k1)
      descoped_k2 = Schema.Utils.descope(k2)

      cond do
        descoped_k1 < descoped_k2 ->
          true

        descoped_k1 == descoped_k2 ->
          v1[:extension] <= v2[:extension]

        true ->
          false
      end
    end)
  end

  @spec parse_profiles_from_params(map()) :: Schema.Utils.string_set_t()
  defp parse_profiles_from_params(params) do
    profiles = params["profiles"]

    if is_binary(profiles) && String.length(profiles) > 0 do
      profiles
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> MapSet.new()
    else
      MapSet.new(empty_string_list())
    end
  end

  # empty_string_list only exists to satisfy the success typing of parse_profiles_from_params.
  @spec empty_string_list() :: [String.t()]
  defp empty_string_list() do
    []
  end

  @doc """
    Returns the list of profiles.
  """
  @spec get_profiles(map) :: map
  def get_profiles(params) do
    extensions = SchemaController.parse_options(SchemaController.extensions(params))
    Schema.profiles_filter_extensions(extensions)
  end
end
