defmodule Schema.Cache do
  @moduledoc """
  This module keeps the schema in memory, aka schema cache.
  """

  alias __MODULE__
  alias Schema.Utils

  require Logger

  @enforce_keys [:version, :dictionary, :categories, :common, :classes, :objects]
  defstruct ~w[version dictionary common categories classes objects]a

  @spec new(map()) :: Schema.Cache.t()
  def new(version) do
    %Cache{
      version: version,
      dictionary: Map.new(),
      categories: Map.new(),
      common: Map.new(),
      classes: Map.new(),
      objects: Map.new()
    }
  end

  @type t() :: %Cache{}
  @type class_t() :: map()
  @type object_t() :: map()
  @type category_t() :: map()
  @type dictionary_t() :: map()

  # The schema JSON file extention.
  @schema_file ".json"

  # The default location of the schema files.
  @data_dir "../schema"
  @version_file "version.json"

  @categories_file "categories.json"
  @dictionary_file "dictionary.json"

  @events_dir "events"
  @objects_dir "objects"

  @doc """
  Load the schema files and initialize the cache.
  """
  @spec init :: Cache.t()
  def init() do
    home = data_dir()

    Logger.info(fn -> "#{inspect(__MODULE__)}: loading schema: #{home}" end)

    version = read_version(home)
    Logger.info(fn -> "#{inspect(__MODULE__)}: schema version: #{inspect(version)}" end)

    categories = read_categories(home)
    dictionary = read_dictionary(home)
    {common, classes} = read_classes(home, categories.attributes)
    objects = read_objects(home)

    dictionary = Utils.update_dictionary(dictionary, common, classes, objects)
    objects = Utils.update_objects(dictionary, objects)

    new(version)
    |> set_categories(categories)
    |> set_dictionary(dictionary)
    |> set_common(common)
    |> set_classes(classes)
    |> set_objects(objects)
  end

  @spec to_uid(nil | binary) :: atom
  def to_uid(nil), do: nil

  def to_uid(name) do
    name |> String.downcase() |> String.to_atom()
  end

  @spec version(Schema.Cache.t()) :: String.t()
  def version(%Cache{version: version}), do: version[:version]

  @spec dictionary(Schema.Cache.t()) :: dictionary_t()
  def dictionary(%Cache{dictionary: dictionary}), do: dictionary

  @spec categories(Schema.Cache.t()) :: map()
  def categories(%Cache{categories: categories}), do: categories

  @spec categories(Schema.Cache.t(), any) :: nil | category_t()
  def categories(%Cache{categories: categories, classes: classes}, id) do
    case Map.get(categories.attributes, id) do
      nil ->
        nil

      category ->
        add_classes({id, category}, classes)
    end
  end

  @spec classes(Schema.Cache.t()) :: list
  def classes(%Cache{classes: classes}), do: classes

  @spec classes(Schema.Cache.t(), atom()) :: nil | class_t()
  def classes(%Cache{dictionary: dictionary, common: common}, :event) do
    enrich(common, dictionary.attributes)
  end

  def classes(%Cache{dictionary: dictionary, classes: classes}, id) do
    case Map.get(classes, id) do
      nil ->
        nil

      class ->
        enrich(class, dictionary.attributes)
    end
  end

  @spec objects(Schema.Cache.t()) :: map()
  def objects(%Cache{objects: objects}), do: objects

  @spec objects(Schema.Cache.t(), any) :: nil | object_t()
  def objects(%Cache{dictionary: dictionary, objects: objects}, id) do
    case Map.get(objects, id) do
      nil ->
        nil

      object ->
        enrich(object, dictionary.attributes)
    end
  end

  defp add_classes({id, category}, classes) do
    category_id = Atom.to_string(id)

    list =
      Enum.filter(classes, fn {_name, class} ->
        Map.get(class, :category_id) == category_id
      end)

    Map.put(category, :classes, list)
  end

  defp enrich(map, dictionary) do
    attributes =
      Enum.map(map.attributes, fn {name, attribute} ->
        case dictionary[name] do
          nil ->
            Logger.warn("undefined attribute: #{name}")
            {name, attribute}

          base ->
            {name, Utils.deep_merge(base, attribute)}
        end
      end)

    Map.put(map, :attributes, attributes)
  end

  # The location of the schema files.
  @spec data_dir :: String.t()
  def data_dir() do
    Application.get_env(:schema_server, __MODULE__) |> Keyword.get(:home) ||
      @data_dir
  end

  defp read_version(home) do
    file = Path.join(home, @version_file)

    if File.regular?(file) do
      read_json_file(file)
    else
      Logger.warn("version file #{file} not found")
      "unknown"
    end
  end

  defp read_categories(home) do
    Path.join(home, @categories_file) |> read_json_file
  end

  defp read_dictionary(home) do
    Path.join(home, @dictionary_file) |> read_json_file
  end

  defp read_classes(home, categories) do
    classes = read_schema_files(Path.join(home, @events_dir), Map.new())
    base = Map.get(classes, :event)

    classes =
      Stream.map(classes, fn {name, map} -> {name, resolve_extends(classes, map)} end)
      |> Stream.filter(fn {_name, class} -> Map.has_key?(class, :uid) end)
      |> Stream.map(fn class -> enrich_class(class, categories) end)
      |> Enum.to_list()
      |> Map.new()

    {base, classes}
  end

  # Add category_id, class_id, and event_uid
  defp enrich_class({name, class}, categories) do
    data =
      class
      |> add_event_uid()
      |> add_class_id()
      |> add_category_id(categories)

    {name, data}
  end

  defp add_event_uid(data) do
    Map.update!(data, :attributes, fn attributes ->
      id = attributes[:outcome_id] || %{}
      uid = attributes[:event_uid] || %{}

      enum =
        case id[:enum] do
          nil ->
            %{"0" => "UNKNOWN"}

          values ->
            class_id = data[:uid] || 0
            caption = data[:name] || "UNKNOWN"

            for {key, val} <- values, into: %{} do
              id = Integer.to_string(class_id * 1000 + String.to_integer(Atom.to_string(key)))
              name = caption <> ": " <> val[:name]

              {String.to_atom(id), Map.put(val, :name, name)}
            end
        end

      Map.put(attributes, :event_uid, Map.put(uid, :enum, enum))
    end)
  end

  defp add_class_id(data) do
    class_id = data.uid |> Integer.to_string() |> String.to_atom()

    enum = %{
      :name => data.name,
      :description => data[:description]
    }

    put_in(data, [:attributes, :class_id, :enum], %{class_id => enum})
  end

  defp add_category_id(data, categories) do
    category_id = data.category_id |> String.to_atom()

    category = categories[category_id]

    if category == nil do
      exit("#{data.name} has invalid category: #{data.category_id}")
    end

    update_in(data, [:attributes, :category_id, :enum], fn _enum ->
      id = Integer.to_string(category.id) |> String.to_atom()
      %{id => category}
    end)
  end

  defp read_objects(home) do
    read_schema_files(Path.join(home, @objects_dir), Map.new())
    |> resolve_extends()
    |> Enum.filter(fn {key, _object} ->
      # remove abstract objects
      !String.starts_with?(Atom.to_string(key), "_")
    end)
    |> Map.new()
  end

  defp resolve_extends(data) do
    Enum.map(data, fn {name, map} -> {name, resolve_extends(data, map)} end)
  end

  defp resolve_extends(data, map) do
    case map[:extends] do
      nil ->
        map

      key ->
        case data[String.to_atom(key)] do
          nil ->
            exit("Error: #{map.name} extends undefined class: #{key}")

          base ->
            base = resolve_extends(data, base)
            attributes = Utils.deep_merge(base.attributes, map.attributes)

            Map.merge(base, map)
            |> Map.delete(:extends)
            |> Map.put(:attributes, attributes)
        end
    end
  end

  defp read_schema_files(path, acc) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, files} ->
          files
          |> Stream.map(fn file -> Path.join(path, file) end)
          |> Enum.reduce(acc, fn file, map -> read_schema_files(file, map) end)

        error ->
          Logger.warn("unable to access #{path} directory. Error: #{inspect(error)}")
          raise error
      end
    else
      if Path.extname(path) == @schema_file do
        data = read_json_file(path)
        Map.put(acc, String.to_atom(data.type), data)
      else
        acc
      end
    end
  end

  defp read_json_file(file) do
    data = File.read!(file)

    case Jason.decode(data, keys: :atoms) do
      {:ok, json} ->
        json

      {:error, error} ->
        message = Jason.DecodeError.message(error)
        Logger.error("Invalid JSON file: #{file}. Error: #{message}")
        exit(message)
    end
  end

  defp set_dictionary(%Cache{} = schema, dictionary) do
    struct(schema, dictionary: dictionary)
  end

  defp set_categories(%Cache{} = schema, categories) do
    struct(schema, categories: categories)
  end

  defp set_common(%Cache{} = schema, common) do
    struct(schema, common: common)
  end

  defp set_classes(%Cache{} = schema, classes) do
    struct(schema, classes: classes)
  end

  defp set_objects(%Cache{} = schema, objects) do
    struct(schema, objects: objects)
  end
end
