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
    get "/categories/:id", PageController, :categories

    get "/dictionary", PageController, :dictionary
    get "/base_event", PageController, :base_event

    get "/classes", PageController, :classes
    get "/classes/:id", PageController, :classes

    get "/objects", PageController, :objects
    get "/objects/:id", PageController, :objects

    get "/guidelines", PageController, :guidelines
    get "/data_types", PageController, :data_types
  end

  # Other scopes may use custom stacks.
  scope "/api", SchemaWeb do
    pipe_through :api

    get "/", SchemaController, :categories
    get "/categories", SchemaController, :categories
    get "/categories/:id", SchemaController, :categories

    get "/dictionary", SchemaController, :dictionary
    get "/base_event", SchemaController, :base_event

    get "/objects", SchemaController, :objects
    get "/objects/:id", SchemaController, :objects

    get "/classes", SchemaController, :classes
    get "/classes/:id", SchemaController, :classes

    post "/translate", SchemaController, :translate
    post "/validate", SchemaController, :validate
  end

  scope "/sample", SchemaWeb do
    pipe_through :api

    get "/base_event", SchemaController, :sample_event
    get "/objects/:id", SchemaController, :sample_object
    get "/classes/:id", SchemaController, :sample_class
  end
end
