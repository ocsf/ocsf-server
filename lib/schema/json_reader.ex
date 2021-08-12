defmodule Schema.JsonReader do
  @moduledoc """
    Provides functions to read and parse json files, and then resolving the included files.
  """
  use GenServer

  alias Schema.Utils
  require Logger

  # The default location of the schema files
  @data_dir "../schema"
  @events_dir "events"
  @objects_dir "objects"

  # The schema JSON file extension
  @schema_file ".json"

  # The Schema version file
  @version_file "version.json"

  # The include directive
  @include :"$include"

  @categories_file "categories.json"
  @dictionary_file "dictionary.json"

  def start_link(opts \\ nil) do
    Logger.info("starting json reader with: #{inspect(opts)}")
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  The location of the schema files.
  """
  @spec data_dir :: String.t()
  def data_dir() do
    home = Application.get_env(:schema_server, __MODULE__) |> Keyword.get(:home) || @data_dir
    Logger.info(fn -> "#{inspect(__MODULE__)}: schema directory: #{home}" end)
    home
  end

  @spec read_version() :: map()
  def read_version() do
    GenServer.call(__MODULE__, :read_version)
  end

  @spec read_categories() :: term()
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

  @spec profile() :: :ok
  def profile() do
    GenServer.cast(__MODULE__, {:profile, nil})
  end

  @spec profile(String.t()) :: :ok
  def profile(name) do
    GenServer.cast(__MODULE__, {:profile, name})
  end

  @spec cleanup() :: :ok
  def cleanup() do
    GenServer.cast(__MODULE__, :delete)
  end

  @impl true
  @spec init(String.t()) :: {:ok, term()}
  def init(ext_dir) do
    init_cache()
    {:ok, {data_dir(), ext_dir}}
  end

  @impl true
  def handle_call(:read_version, _from, {home, _ext_dir} = state) do
    {:reply, read_version(home), state}
  end

  @impl true
  def handle_call(:read_categories, _from, {home, ext_dir} = state) do
    {:reply, read_categories(home, ext_dir), state}
  end

  @impl true
  def handle_call(:read_dictionary, _from, {home, ext_dir} = state) do
    {:reply, read_dictionary(home, ext_dir), state}
  end

  @impl true
  def handle_call(:read_objects, _from, {home, ext_dir} = state) do
    {:reply, read_objects(home, ext_dir), state}
  end

  @impl true
  def handle_call(:read_classes, _from, {home, ext_dir} = state) do
    {:reply, read_classes(home, ext_dir), state}
  end

  @impl true
  def handle_cast({:profile, name}, {home, _ext_dir}) do
    {:noreply, {home, name}}
  end

  @impl true
  def handle_cast(:delete, state) do
    delete()
    {:noreply, state}
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

  defp read_categories(home, nil) do
    Path.join(home, @categories_file) |> read_json_file()
  end

  defp read_categories(home, ext_dir) do
    Path.join(home, @categories_file)
    |> read_json_file()
		|> merge_json_file(Path.join(home, ext_dir), @categories_file)
  end

  defp read_dictionary(home, nil) do
    Path.join(home, @dictionary_file) |> read_json_file()
  end

  defp read_dictionary(home, ext_dir) do
    Path.join(home, @dictionary_file)
    |> read_json_file()
		|> merge_json_file(Path.join(home, ext_dir), @dictionary_file)
  end

  defp read_objects(home, nil) do
    read_schema_files(Map.new(), home, Path.join(home, @objects_dir))
  end

  defp read_objects(home, ext_dir) do
    Map.new()
    |> read_schema_files(home, Path.join(home, @objects_dir))
    |> scan_schema_files(home, Path.join(home, ext_dir), @objects_dir)
  end

  defp read_classes(home, nil) do
		Map.new()
		|> read_schema_files(home, Path.join(home, @events_dir))
  end

  defp read_classes(home, ext_dir) do
    Map.new()
    |> read_schema_files(home, Path.join(home, @events_dir))
    |> scan_schema_files(home, Path.join(home, ext_dir), @events_dir)
  end

  # scan for schema extension files
  defp scan_schema_files(acc, home, path, directory) do
    Logger.info("scan_schema_files: #{Path.join(path, directory)}")

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
    else
      acc
    end
  end

  defp read_schema_files(acc, home, path) do
    if File.dir?(path) do
      Logger.info("read_schema_files: #{path}")

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
        data = read_json_file(path) |> resolve_includes(home)
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
        Logger.error("invalid JSON file: #{file}. Error: #{message}")
        raise message
    end
  end

  def merge_json_file(map, path, filename) do
    if File.dir?(path) do
      Logger.info("merge_json_file: #{path} #{filename}")

      case File.ls(path) do
        {:ok, files} ->
          files
          |> Stream.map(fn file -> Path.join(path, file) end)
          |> Enum.reduce(map, fn file, map -> merge_json_file(map, file, filename) end)

        error ->
          Logger.warn("merge_json_file: unable to access #{path} directory. Error: #{inspect(error)}")
          raise error
      end
    else
      if Path.basename(path) == filename do
				read_json_file(path) |> Utils.deep_merge(map)
      else
        map
      end
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

      file when is_binary(file) ->
        include_traits(home, file, data)

      files when is_list(files) ->
        Enum.reduce(files, data, fn file, acc -> include_traits(home, file, acc) end)
    end
    |> include_enums(home)
  end

  defp include_traits(home, file, data) do
    included =
      case get(file) do
        [] ->
          Path.join(home, file)
          |> read_json_file()
          |> resolve_includes(home)
          |> put(data)

        [{_, cached}] ->
          cached
      end

    attributes =
      Schema.Utils.deep_merge(included.attributes, Map.delete(data.attributes, @include))

    Map.put(data, :attributes, attributes)
  end

  defp include_enums(class, home) do
    Map.update(class, :attributes, [], fn attributes -> merge_enums(home, attributes) end)
  end

  defp merge_enums(home, attributes) do
    Enum.map(
      attributes,
      fn {name, attribute} ->
        {name, merge_enum_file(home, attribute)}
      end
    )
    |> Map.new()
  end

  defp merge_enum_file(home, attribute) do
    case Map.get(attribute, @include) do
      nil ->
        attribute

      file ->
        merge_enum_file(home, file, Map.delete(attribute, @include))
    end
  end

  defp merge_enum_file(home, file, attribute) do
    included =
      case get(file) do
        [] ->
          Path.join(home, file)
          |> read_json_file()
          |> put(file)

        [{_, cached}] ->
          cached
      end

    Schema.Utils.deep_merge(included, attribute)
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

  defp delete() do
    :ets.delete_all_objects(__MODULE__)
  end
end
