defmodule Schema.JsonReader do
  @moduledoc """
    Provides functions to read, parse, merge json files, and resolving the included files.
  """
  use GenServer

  alias Schema.Utils

  require Logger

  # The default location of the schema files
  @data_dir "schema"
  @events_dir "events"
  @objects_dir "objects"

  # The schema uses JSON files
  @schema_file ".json"

  # The Schema version file
  @version_file "version.json"

  @categories_file "categories.json"
  @dictionary_file "dictionary.json"

  # The Schema extension file
  @extension_file "extension.json"

  # The include directive
  @include :"$include"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec read_version() :: map()
  def read_version() do
    GenServer.call(__MODULE__, :read_version)
  end

  @spec read_categories() :: map()
  def read_categories() do
    GenServer.call(__MODULE__, :read_categories)
  end

  @spec read_dictionary() :: map()
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

  @spec read_profiles() :: map()
  def read_profiles() do
    GenServer.call(__MODULE__, :read_profiles)
  end

  @spec reset() :: :ok
  def reset() do
    GenServer.cast(__MODULE__, {:reset, []})
  end

  @spec reset(String.t()) :: :ok
  def reset(name) when is_binary(name) do
    GenServer.cast(__MODULE__, {:reset, [name]})
  end

  def reset(list) when is_list(list) do
    GenServer.cast(__MODULE__, {:reset, list})
  end

  @spec extensions :: any
  def extensions() do
    GenServer.call(__MODULE__, :extensions)
  end

  @spec cleanup() :: :ok
  def cleanup() do
    GenServer.cast(__MODULE__, :delete)
  end

  @impl true
  @spec init(String.t() | list()) :: {:ok, term()}
  def init(ext_dir) when is_binary(ext_dir) do
    init([ext_dir])
  end

  def init(ext_dir) do
    init_cache()
    home = data_dir()
    version = read_version(home)
    extensions = extensions(home, ext_dir)

    Logger.info(fn -> "#{inspect(__MODULE__)} schema    : #{home}" end)
    Logger.info(fn -> "#{inspect(__MODULE__)} version   : #{version.version}" end)

    Logger.info(fn ->
      "#{inspect(__MODULE__)} extensions: #{Jason.encode!(extensions, pretty: true)}"
    end)

    {:ok, {home, extensions}}
  end

  @impl true
  def handle_call(:read_version, _from, {home, _ext} = state) do
    {:reply, read_version(home), state}
  end

  @impl true
  def handle_call(:read_categories, _from, {home, ext} = state) do
    {:reply, read_categories(home, ext), state}
  end

  @impl true
  def handle_call(:read_dictionary, _from, {home, ext} = state) do
    {:reply, read_dictionary(home, ext), state}
  end

  @impl true
  def handle_call(:read_objects, _from, {home, ext} = state) do
    {:reply, read_objects(home, ext), state}
  end

  @impl true
  def handle_call(:read_classes, _from, {home, ext} = state) do
    {:reply, read_classes(home, ext), state}
  end

  @impl true
  def handle_call(:read_profiles, _from, {home, ext} = state) do
    {:reply, read_profiles(home, ext), state}
  end

  @impl true
  def handle_call(:extensions, _from, {_home, ext} = state) do
    extensions = Enum.map(ext, fn ext -> {ext[:type], ext} end) |> Map.new()
    {:reply, extensions, state}
  end

  @impl true
  def handle_cast({:reset, ext}, {home, _ext}) do
    {:noreply, {home, extensions(home, ext)}}
  end

  @impl true
  def handle_cast(:delete, state) do
    delete()
    {:noreply, state}
  end

  defp data_dir() do
    (Application.get_env(:schema_server, __MODULE__) |> Keyword.get(:home) || @data_dir)
    |> Path.absname()
    |> Path.expand()
  end

  defp read_version(home) do
    file = Path.join(home, @version_file)

    if File.regular?(file) do
      read_json_file(file)
    else
      Logger.warn("#{inspect(__MODULE__)} version file #{file} not found")
      %{"version" => "0.0.0"}
    end
  end

  defp read_categories(home, []) do
    Path.join(home, @categories_file) |> read_json_file()
  end

  defp read_categories(home, extensions) do
    categories = Path.join(home, @categories_file) |> read_json_file()

    Enum.reduce(extensions, categories, fn ext, acc ->
      merge_extension_file(acc, ext, @categories_file)
    end)
  end

  defp read_dictionary(home, []) do
    Path.join(home, @dictionary_file) |> read_json_file()
  end

  defp read_dictionary(home, extensions) do
    dictionary = Path.join(home, @dictionary_file) |> read_json_file()

    Enum.reduce(extensions, dictionary, fn ext, acc ->
      merge_extension_file(acc, ext, @dictionary_file)
    end)
  end

  defp read_objects(home, []) do
    read_schema_dir(Map.new(), home, Path.join(home, @objects_dir))
  end

  defp read_objects(home, extensions) do
    objects = read_schema_dir(Map.new(), home, Path.join(home, @objects_dir))

    Enum.reduce(extensions, objects, fn ext, acc ->
      read_extension_dir(acc, home, ext, @objects_dir)
    end)
  end

  defp read_classes(home, []) do
    read_schema_dir(Map.new(), home, Path.join(home, @events_dir))
  end

  defp read_classes(home, extensions) do
    events = read_schema_dir(Map.new(), home, Path.join(home, @events_dir))

    Enum.reduce(extensions, events, fn ext, acc ->
      read_extension_dir(acc, home, ext, @events_dir)
    end)
  end

  defp read_schema_dir(acc, home, path) do
    if File.dir?(path) do
      Logger.info(fn -> "#{inspect(__MODULE__)} read files: #{path}" end)

      case File.ls(path) do
        {:ok, files} ->
          files
          |> Stream.map(fn file -> Path.join(path, file) end)
          |> Enum.reduce(acc, fn file, map -> read_schema_dir(map, home, file) end)

        error ->
          error("unable to access #{path} directory. Error: #{inspect(error)}")
      end
    else
      if Path.extname(path) == @schema_file do
        data = read_json_file(path) |> resolve_includes(home)
        Map.put(acc, String.to_atom(data[:type]), data)
      else
        acc
      end
    end
  end

  defp read_json_file(file) do
    case File.read(file) do
      {:ok, data} ->
        case Jason.decode(data, keys: :atoms) do
          {:ok, json} ->
            json

          {:error, error} ->
            message = Jason.DecodeError.message(error)
            error("invalid JSON file: #{file}. Error: #{message}")
        end

      {:error, :enoent} ->
        error("file #{file} does not exist")

      {:error, :eacces} ->
        error("missing permission for reading #{file} file")

      {:error, :eisdir} ->
        error("file #{file} is a directory")

      {:error, reason} ->
        error("unable to read #{file} file. Reason: #{reason}")
    end
  end

  defp merge_extension_file(acc, ext, file) do
    path = Path.join(ext[:path], file)

    if File.regular?(path) do
      Logger.debug(fn -> "#{inspect(__MODULE__)} read file: [#{ext[:type]}] #{path}" end)

      map = read_json_file(path)

      ext_type = ext[:type]
      ext_uid = ext[:uid]

      attributes =
        if map[:type] == "category" do
          Enum.map(map[:attributes], fn {name, value} ->
            updated = add_extension(value, ext_type, ext_uid)
            {Utils.to_uid(ext_type, name), updated}
          end)
        else
          Enum.map(map[:attributes], fn {name, value} ->
            updated = add_extension(value, ext_type, ext_uid)
            {name, updated}
          end)
        end
        |> Map.new()

      Map.put(
        acc,
        :attributes,
        Map.merge(acc[:attributes], attributes, fn key, v1, v2 ->
          Logger.warn(
            "dictionary: '#{ext[:type]}' extension attempts to overwrite '#{key}': #{inspect(v1)} with #{inspect(v2)}"
          )

          v1
        end)
      )
    else
      acc
    end
  end

  defp read_extension_dir(acc, home, ext, dir) do
    path = Path.join(ext[:path], dir)

    if File.dir?(path) do
      read_extension_files(acc, home, ext, path)
    else
      acc
    end
  end

  defp read_extension_files(acc, home, ext, path) do
    if File.dir?(path) do
      Logger.info(fn -> "#{inspect(__MODULE__)} [#{ext[:type]}] read files: #{path}" end)

      case File.ls(path) do
        {:ok, files} ->
          files
          |> Stream.map(fn file -> Path.join(path, file) end)
          |> Enum.reduce(acc, fn file, map -> read_extension_files(map, home, ext, file) end)

        error ->
          Logger.warn("unable to access #{path} directory. Error: #{inspect(error)}")
          System.stop(0)
      end
    else
      if Path.extname(path) == @schema_file do
        Logger.debug(fn -> "#{inspect(__MODULE__)} [#{ext[:type]}] read file: #{path}" end)

        data =
          read_json_file(path)
          |> resolve_extension_includes(home, ext)
          |> add_extension(ext[:type], ext[:uid])

        name = Utils.to_uid(ext[:type], data[:type])
        Map.put(acc, name, data)
      else
        acc
      end
    end
  end

  defp add_extension(map, type, uid) do
    map
    |> Map.put(:extension, type)
    |> Map.put(:extension_id, uid)
  end

  defp resolve_includes(data, home) do
    read_included_files(data, Map.get(data, :attributes), fn file ->
      resolve_file(home, file)
    end)
  end

  defp resolve_extension_includes(data, home, ext) do
    read_included_files(data, Map.get(data, :attributes), fn file ->
      resolve_file(home, ext, file)
    end)
  end

  defp read_included_files(data, nil, _resolver), do: data

  defp read_included_files(data, attributes, resolver) do
    case Map.get(attributes, @include) do
      nil ->
        data

      file when is_binary(file) ->
        include_traits(resolver, file, data)

      files when is_list(files) ->
        Enum.reduce(files, data, fn file, acc -> include_traits(resolver, file, acc) end)
    end
    |> include_enums(resolver)
  end

  defp include_traits(resolver, file, data) do
    included = get_included_file(resolver, file)
    attributes = Utils.deep_merge(included[:attributes], Map.delete(data[:attributes], @include))
    Map.put(data, :attributes, attributes)
  end

  defp include_enums(class, resolver) do
    Map.update(class, :attributes, [], fn attributes -> merge_enums(resolver, attributes) end)
  end

  defp merge_enums(resolver, attributes) do
    Enum.map(
      attributes,
      fn {name, attribute} ->
        {name, merge_enum_file(resolver, attribute)}
      end
    )
    |> Map.new()
  end

  defp merge_enum_file(resolver, attribute) do
    case Map.get(attribute, @include) do
      nil ->
        attribute

      file ->
        get_included_file(resolver, file) |> Utils.deep_merge(Map.delete(attribute, @include))
    end
  end

  defp get_included_file(resolver, file) do
    path = resolver.(file)
    Logger.debug(fn -> "#{inspect(__MODULE__)} include file #{path}" end)

    case cache_get(path) do
      [] ->
        read_json_file(path) |> update_profile_attributes(file) |> cache_put(path)

      [{_, cached}] ->
        cached
    end
  end

  defp update_profile_attributes(data, file) do
    profile =
      case data[:meta] do
        "profile" ->
          update_profile(data[:name], data[:type], file)

        _ ->
          nil
      end

    case data[:annotations] do
      nil ->
        data

      annotations ->
        Map.update(data, :attributes, [], fn attributes ->
          add_annotated_attributes(attributes, profile, annotations)
        end)
    end
  end

  defp update_profile(name, type, file) do
    profiles =
      case cache_get(:profiles) do
        [{_, cached}] -> cached
        [] -> %{}
      end

    case profiles[type] do
      nil ->
        Logger.info("Schema.JsonReader profiles: #{file} defines a new profile: #{type}")

        Map.put(profiles, type, %{name: name, type: type})
        |> cache_put(:profiles)

      _profile ->
        Logger.warn("Schema.JsonReader profiles: #{file} overwrites an existing profile: #{type}")
    end

    type
  end

  defp read_profiles(_home, []) do
    case cache_get(:profiles) do
      [{_, cached}] -> cached
      [] -> %{}
    end
  end

  defp read_profiles(home, _extensions) do
    read_profiles(home, [])
  end

  defp add_annotated_attributes(attributes, nil, annotations) do
    Enum.map(attributes, fn {name, attribute} ->
      {name, Utils.deep_merge(annotations, attribute)}
    end)
    |> Map.new()
  end

  defp add_annotated_attributes(attributes, profile, annotations) do
    Enum.map(attributes, fn {name, attribute} ->
      {name, Utils.deep_merge(annotations, Map.put(attribute, :profile, profile))}
    end)
    |> Map.new()
  end

  # Extensions
  @spec extensions(any, binary | maybe_improper_list) :: any
  def extensions(home, path) when is_binary(path) do
    find_extensions(home, path, [])
  end

  def extensions(home, list) when is_list(list) do
    Enum.reduce(list, [], fn path, acc ->
      find_extensions(home, String.trim(path), acc)
    end)
    |> Enum.uniq_by(fn ext -> ext[:path] end)
  end

  defp find_extensions(home, path, list) do
    path =
      if File.dir?(path) do
        path
      else
        Path.join(home, path) |> Path.absname()
      end

    if File.dir?(path) do
      find_extensions(path, list)
    else
      Logger.warn("invalid extensions path: #{path}")
      list
    end
  end

  defp find_extensions(path, list) do
    if File.dir?(path) do
      case read_extension(path) do
        false ->
          case File.ls(path) do
            {:ok, files} ->
              files
              |> Enum.map(fn file -> Path.join(path, file) end)
              |> Enum.reduce(list, fn file, acc -> find_extensions(file, acc) end)

            error ->
              error("unable to access #{path} directory. Error: #{inspect(error)}")
          end

        data ->
          [Map.put(data, :path, path) | list]
      end
    else
      list
    end
  end

  defp read_extension(path) do
    file = Path.join(path, @extension_file)

    if File.regular?(file) do
      read_json_file(file)
    else
      false
    end
  end

  defp error(message) do
    Logger.error(message)
    System.stop(1)
  end

  defp resolve_file(home, file) do
    path = Path.join(home, file)

    if File.regular?(path) do
      path
    else
      error("file #{path} not found in #{home}")
    end
  end

  defp resolve_file(home, ext, file) do
    path = Path.join(ext[:path], file)

    if File.regular?(path) do
      path
    else
      path = Path.join(home, file)

      if File.regular?(path) do
        path
      else
        error("file #{path} not found in [#{ext[:path]}, #{home}]")
      end
    end
  end

  # ETS cache for the included json files
  defp init_cache() do
    name = __MODULE__

    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:set, :protected, :named_table])

      _ ->
        error("ETS table with name #{name} already exists.")
    end
  end

  defp cache_put(data, path) do
    :ets.insert(__MODULE__, {path, data})
    data
  end

  defp cache_get(path) do
    :ets.lookup(__MODULE__, path)
  end

  defp delete() do
    :ets.delete_all_objects(__MODULE__)
  end
end
