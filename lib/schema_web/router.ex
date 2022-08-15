# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule SchemaWeb.Router do
  use SchemaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SchemaWeb do
    pipe_through :browser

    get "/", PageController, :categories
    get "/categories", PageController, :categories

    get "/categories/:id", PageController, :categories
    get "/categories/:extension/:id", PageController, :categories

    get "/dictionary", PageController, :dictionary
    get "/dictionary/:extension", PageController, :dictionary

    get "/base_event", PageController, :base_event

    get "/classes", PageController, :classes
    get "/classes/:id", PageController, :classes
    get "/classes/:extension/:id", PageController, :classes

    get "/objects", PageController, :objects
    get "/objects/:id", PageController, :objects
    get "/objects/:extension/:id", PageController, :objects

    get "/guidelines", PageController, :guidelines
    get "/data_types", PageController, :data_types
  end

  # Other scopes may use custom stacks.
  scope "/api", SchemaWeb do
    pipe_through :api

    get "/extensions", SchemaController, :extensions
    get "/profiles", SchemaController, :profiles

    get "/categories", SchemaController, :categories
    get "/categories/:id", SchemaController, :categories
    get "/categories/:extension/:id", SchemaController, :categories

    get "/dictionary", SchemaController, :dictionary
    get "/dictionary/:extension", SchemaController, :dictionary

    get "/base_event", SchemaController, :base_event

    get "/objects", SchemaController, :objects
    get "/objects/:id", SchemaController, :objects
    get "/objects/:extension/:id", SchemaController, :objects

    get "/classes", SchemaController, :classes
    get "/classes/:id", SchemaController, :classes
    get "/classes/:extension/:id", SchemaController, :classes

    get "/schema", SchemaController, :schema
    get "/schema/:extension", SchemaController, :schema

    get "/data_types", SchemaController, :data_types
    get "/version", SchemaController, :version

    post "/translate", SchemaController, :translate
    post "/validate", SchemaController, :validate
  end

  scope "/export", SchemaWeb do
    pipe_through :api

    get "/objects", SchemaController, :export_objects
    get "/classes", SchemaController, :export_classes
    get "/category/:id", SchemaController, :export_category
    get "/schema", SchemaController, :export_schema
  end

  scope "/sample", SchemaWeb do
    pipe_through :api

    get "/base_event", SchemaController, :sample_event

    get "/objects/:id", SchemaController, :sample_object
    get "/objects/:extension/:id", SchemaController, :sample_object

    get "/classes/:id", SchemaController, :sample_class
    get "/classes/:extension/:id", SchemaController, :sample_class
  end
end
