# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule SchemaWeb.ObjectSchemaController do
  @moduledoc """
  The controller which generates JSON schemas for OCSF Objects.
  """

  use SchemaWeb, :controller
  import PhoenixSwagger

  swagger_path :show do
    get("/api/v2/objects/{name}")

    tag("JSON Schema")
    summary("Describe an OCSF Object as a JSON Schema")

    description("""
    Return a description of the given OCSF object as a Draft 07 JSON Schema.
    """)

    parameters do
      name(:name, :string, "Object Name", required: true)
    end

    produces("application/json")

    response(200, "Success")
    response(404, "Not Found")
  end

  @spec show(Plug.Conn.t(), any) :: Plug.Conn.t()
  def show(conn, %{"id" => object_name}) do
    options = [
      ref_base: SchemaWeb.Endpoint.url(),
      ref_endpoint_objects: "/api/v2/objects",
      include_formats: true,
      include_java_names: true
    ]

    object =
      object_name
      |> String.to_atom()
      |> Schema.clean_object_filter_extensions_profiles(nil, nil)
      |> Schema.JsonSchema.encode(options)

    case object do
      result when map_size(result) == 0 -> send_resp(conn, :not_found, "")
      result -> json(conn, result)
    end
  end
end
