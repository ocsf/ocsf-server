defmodule Schema.JsonReader do
  @moduledoc """
    Provides functions to read and parse json file, resolving the included files.
  """

  use GenServer

  alias Schema.Utils
  require Logger

  # The default location of the schema files
  @data_dir "../schema"
  @events_dir "events"
  @objects_dir "objects"
  @ext_dir "extensions"

  # The schema JSON file extension
  @schema_file ".json"

  # The Schema version file
  @version_file "version.json"

  # The include directive
  @include :"$include"

  @categories_file "categories.json"
  @dictionary_file "dictionary.json"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  The location of the schema files.  
  """
  @spec data_dir :: String.t()
  def data_dir() do
    :schema_server
    |> Application.get_env(__MODULE__)
    |> Keyword.get(:home) || @data_dir
  end

  @spec read_version() :: map()
  def read_version() do
    GenServer.call(__MODULE__, :read_version)
  end

  @spec read_categories() :: any()
  def read_categories() do
    GenServer.call(__MODULE__, :read_categories)
  end

  @spec read_dictionary() :: any()
  def read_dictionary() do
    GenServer.call(__MODULE__, :read_dictionary)
  end

  @spec read_objects() :: map()
  def read_objects() do
    GenServer.call(__MODULE__, :read_objects)
  end

  @spec read_classes() :: map()
  def read_classes() do
    GenServer.call(__MODULE__, :read_classes)
  end

  @doc """
  Reads and decodes a JSON file into a map. It will also resolve the includes.
  """
  @spec read_file(String.t()) :: map()
  def read_file(filename) do
    GenServer.call(__MODULE__, {:read, filename})
  end

  @impl true
  def init(_opts) do
    init_cache()
    home = data_dir()
    Logger.info(fn -> "#{inspect(__MODULE__)}: loading schema: #{home}" end)
    {:ok, home}
  end

  @impl true
  def handle_call({:read, filename}, _from, home) do
    data = read_file(home, filename)
    {:reply, data, home}
  end

  @impl true
  def handle_call(:read_version, _from, home) do
    {:reply, read_version(home), home}
  end

  @impl true
  def handle_call(:read_categories, _from, home) do
    {:reply, read_categories(home), home}
  end

  @impl true
  def handle_call(:read_dictionary, _from, home) do
    {:reply, read_dictionary(home), home}
  end

  @impl true
  def handle_call(:read_objects, _from, home) do
    {:reply, read_objects(home), home}
  end

  @impl true
  def handle_call(:read_classes, _from, home) do
    {:reply, read_classes(home), home}
  end

  defp read_file(home, file) do
    Path.join(home, file) |> read_json_file() |> resolve_includes(home)
  end

  defp read_json_file(file) do
    data = File.read!(file)

    case Jason.decode(data, keys: :atoms) do
      {:ok, json} ->
        json

      {:error, error} ->
        message = Jason.DecodeError.message(error)
        Logger.error("invalid JSON file: #{file}. Error: #{message}")
        raise message
    end
  end

  defp resolve_includes(data, home) do
    resolve_includes(data, Map.get(data, :attributes), home)
  end

  defp resolve_includes(data, nil, _home), do: data

  defp resolve_includes(data, attributes, home) do
    case Map.get(attributes, @include) do
      nil ->
        data

      include when is_binary(include) ->
        include_trait(data, include, home)

      include when is_list(include) ->
        Enum.reduce(include, data, fn file, acc -> include_trait(acc, file, home) end)
    end
    |> include_attributes(home)
  end

  defp include_attributes(data, home) do
    Map.update(
      data,
      :attributes,
      [],
      fn attributes ->
        Enum.map(
          attributes,
          fn {name, attribute} ->
            {name, include(attribute, home)}
          end
        )
        |> Map.new()
      end
    )
  end

  defp include(data, home) do
    case Map.get(data, @include) do
      nil ->
        data

      include ->
        include_json_file(Map.delete(data, @include), include, home)
    end
  end

  defp include_json_file(data, file, home) do
    Path.join(home, file)
    |> read_json_file()
    |> Schema.Utils.deep_merge(data)
  end

  defp include_trait(data, file, home) do
    included =
      case get(file) do
        [] ->
          read_file(home, file) |> put(file)

        [{_, cached}] ->
          cached
      end

    attributes =
      Schema.Utils.deep_merge(included.attributes, Map.delete(data.attributes, @include))

    Map.put(data, :attributes, attributes)
  end

  defp read_version(home) do
    file = Path.join(home, @version_file)

    if File.regular?(file) do
      read_json_file(file)
    else
      Logger.warn("version file #{file} not found")
      "0.0.0"
    end
  end

  defp read_categories(home) do
    Path.join(home, @categories_file)
    |> read_json_file
    |> read_json_files(Path.join(home, @ext_dir), @categories_file)
  end

  defp read_dictionary(home) do
    Path.join(home, @dictionary_file)
    |> read_json_file
    |> read_json_files(Path.join(home, @ext_dir), @dictionary_file)
  end

  defp read_objects(home) do
    Map.new()
    |> read_schema_files(home, Path.join(home, @objects_dir))
    |> scan_schema_files(home, Path.join(home, @ext_dir), @objects_dir)
  end

  defp read_classes(home) do
    Map.new()
    |> read_schema_files(home, Path.join(home, @events_dir))
    |> scan_schema_files(home, Path.join(home, @ext_dir), @events_dir)
  end

  defp read_json_files(map, path, name) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, files} ->
          files
          |> Stream.map(fn file -> Path.join(path, file) end)
          |> Enum.reduce(map, fn file, m -> read_json_files(m, file, name) end)

        error ->
          Logger.warn("unable to access #{path} directory. Error: #{inspect(error)}")
          raise error
      end
    else
      if Path.basename(path) == name do
        Logger.info("reading extension: #{path}")

        read_json_file(path) |> Utils.deep_merge(map)
      else
        map
      end
    end
  end

  defp scan_schema_files(acc, home, path, directory) do
    if File.dir?(path) do
      if Path.basename(path) == directory do
        Logger.info("reading extensions: #{path}")
        read_schema_files(acc, home, path)
      else
        case File.ls(path) do
          {:ok, files} ->
            files
            |> Stream.map(fn name -> Path.join(path, name) end)
            |> Stream.filter(fn p -> File.dir?(p) end)
            |> Enum.reduce(acc, fn file, map -> scan_schema_files(map, home, file, directory) end)

          error ->
            Logger.warn("unable to access #{path} directory. Error: #{inspect(error)}")
            raise error
        end
      end
    end
  end

  defp read_schema_files(acc, home, path) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, files} ->
          files
          |> Stream.map(fn file -> Path.join(path, file) end)
          |> Enum.reduce(acc, fn file, map -> read_schema_files(map, home, file) end)

        error ->
          Logger.warn("unable to access #{path} directory. Error: #{inspect(error)}")
          raise error
      end
    else
      if Path.extname(path) == @schema_file do
        data = read_json_file(home, path)
        Map.put(acc, String.to_atom(data.type), data)
      else
        acc
      end
    end
  end

  defp read_json_file(home, file) do
    file |> read_json_file() |> resolve_includes(home)
  end

  # ETS cache for the included json file
  defp init_cache() do
    name = __MODULE__

    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:set, :protected, :named_table])

      _ ->
        raise "ETS table with name #{name} already exists."
    end
  end

  defp put(data, path) do
    :ets.insert(__MODULE__, {path, data})
    data
  end

  defp get(path) do
    :ets.lookup(__MODULE__, path)
  end

  # defp delete() do
  #   :ets.delete(__MODULE__)
  # end
end
