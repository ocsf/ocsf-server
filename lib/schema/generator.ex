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
defmodule Schema.Generator do
  @moduledoc """
  Random data generator using the event schema.
  """

  use Agent
  use Bitwise

  alias __MODULE__

  require Logger

  defstruct ~w[countries tactics techniques names words files]a

  @spec start :: {:error, any} | {:ok, pid}
  def start(), do: Agent.start(fn -> init() end, name: __MODULE__)

  @spec start_link(any) :: {:error, any} | {:ok, pid}
  def start_link(_), do: Agent.start_link(fn -> init() end, name: __MODULE__)

  @data_dir "priv/data"

  @countries_file "country-and-continent-codes-list.json"

  # MITRE ATT&CK files
  @techniques_file "techniques.json"
  @tactics_file "enterprise-tactics.json"

  @files_file "files.txt"
  @names_file "names.txt"
  @words_file "words.txt"

  def init() do
    dir = Application.app_dir(:schema_server, @data_dir)

    countries = read_countries(Path.join(dir, @countries_file))

    tactics = read_json_file(Path.join(dir, @tactics_file))
    techniques = read_json_file(Path.join(dir, @techniques_file))

    files = read_file_types(Path.join(dir, @files_file))
    names = read_data_file(Path.join(dir, @names_file))
    words = read_data_file(Path.join(dir, @words_file))

    %Generator{
      countries: countries,
      tactics: tactics,
      techniques: techniques,
      files: files,
      names: names,
      words: words
    }
  end

  @doc """
  Generate new event class uid values for a given category.
  """
  @spec update_classes(binary(), integer()) :: any()
  def update_classes(path, uid) when is_binary(path) and is_integer(uid) do
    if File.dir?(path) do
      read_classes(nil, path, [])
      |> Enum.sort()
      |> Enum.reduce(uid, fn {_, file}, next -> update_classes(file, next) end)
    else
      update_class_uid(path, uid)
    end
  end

  @doc """
  Generate an event data using a given class.
  """
  def event(nil), do: nil

  def event(class) do
    Logger.info("generate class: #{inspect(class[:name])}")

    data = generate(class)
    disposition_id = data.disposition_id

    uid =
      if disposition_id >= 0 do
        data.class_id * 1000 + disposition_id
      else
        -1
      end

    Map.put(data, :event_id, uid)
  end

  def generate(class) do
    case class[:type] do
      "fingerprint" -> fingerprint()
      "location" -> location()
      "attack" -> attack()
      _ -> generate_class(class)
    end
  end

  defp generate_class(class) do
    Enum.reduce(class[:attributes], Map.new(), fn {name, field} = attribute, map ->
      if field[:is_array] == true do
        generate_array(field[:requirement], name, attribute, map)
      else
        case field[:type] do
          "object_t" ->
            generate_object(field[:requirement], name, attribute, map)

          nil ->
            Logger.error("Missing class: #{name}")
            map

          _other ->
            generate(attribute, map)
        end
      end
    end)
  end

  # don't generate unmapped and raw_data data
  defp generate({:unmapped, _field}, map), do: map
  defp generate({:raw_data, _field}, map), do: map

  defp generate({name, field}, map) do
    generate_field(field[:requirement], name, field, map)
  end

  #  Generate all required fields
  defp generate_field("required", name, field, map) do
    generate_field(name, field, map)
  end

  defp generate_field("reserved", name, field, map) do
    Logger.debug("reserved: #{name}")
    generate_field(name, field, map)
  end

  #  Generate 80% of the recommended fields
  defp generate_field("recommended", name, field, map) do
    if random(100) > 5 do
      generate_field(name, field, map)
    else
      map
    end
  end

  #  Generate 20% of the optional fields
  defp generate_field(_requirement, name, field, map) do
    if random(100) > 50 do
      generate_field(name, field, map)
    else
      map
    end
  end

  defp generate_field(name, %{type: "integer_t"} = field, map) do
    case field[:enum] do
      nil ->
        Map.put(map, name, random(100))

      enum ->
        generate_enum_data(name, enum, map)
    end
  end

  defp generate_field(name, field, map) do
    Map.put(map, name, generate_data(name, field[:type], field))
  end

  defp generate_enum_data(key, enum, map) do
    name =
      Atom.to_string(key)
      |> String.trim("_id")
      |> String.to_atom()

    id = random_enum(enum)

    if id == -1 do
      Map.put(map, name, word())
    else
      Map.delete(map, name)
    end
    |> Map.put(key, id)
  end

  defp generate_array("required", name, attribute, map) do
    Map.put(map, name, generate_array(attribute))
  end

  defp generate_array("recommended", name, attribute, map) do
    if random(100) > 20 do
      Map.put(map, name, generate_array(attribute))
    else
      map
    end
  end

  defp generate_array(_, name, attribute, map) do
    if random(100) > 90 do
      Map.put(map, name, generate_array(attribute))
    else
      map
    end
  end

  defp generate_array({:coordinates, _field}) do
    [random_float(360, 180), random_float(180, 90)]
  end

  defp generate_array({:loaded_modules, _field}) do
    Enum.map(1..random(5), fn _ -> file_name(4) end)
  end

  defp generate_array({:fingerprints, _field}) do
    Enum.map(1..random(5), fn _ -> fingerprint() end)
    |> Enum.uniq_by(fn map -> Map.get(map, :algorithm_id) end)
  end

  defp generate_array({:image_labels, _field}) do
    words(5)
  end

  defp generate_array({name, field} = attribute) do
    n = random(5)

    case field[:type] do
      "object_t" ->
        generate_objects(n, attribute)

      type ->
        Enum.map(1..n, fn _ -> generate_data(name, type, field) end)
    end
  end

  defp generate_object("required", name, attribute, map) do
    Map.put(map, name, generate_object(attribute))
  end

  defp generate_object("recommended", name, attribute, map) do
    if random(100) > 20 do
      Map.put(map, name, generate_object(attribute))
    else
      map
    end
  end

  defp generate_object(_, name, attribute, map) do
    if random(100) > 90 do
      Map.put(map, name, generate_object(attribute))
    else
      map
    end
  end

  defp generate_object({:file_result, field}) do
    generate_object({:file, field})
  end

  defp generate_object({:file, field}) do
    file =
      field.object_type
      |> String.to_atom()
      |> Schema.objects()
      |> generate()

    filename = file_name(0)

    case Map.get(file, :path) do
      nil ->
        Map.put(file, :name, filename)

      path ->
        Map.put(file, :name, filename)
        |> Map.put(:path, Path.join(path, filename))
    end
    |> Map.delete(:normalized_path)
  end

  defp generate_object({_name, field}) do
    field.object_type
    |> String.to_atom()
    |> Schema.objects()
    |> generate()
  end

  defp generate_objects(n, {:attacks, _field}) do
    Enum.map(1..n, fn _ -> attack() end)
  end

  defp generate_objects(n, {_name, field}) do
    object =
      field.object_type
      |> String.to_atom()
      |> Schema.objects()

    Enum.map(1..n, fn _ -> generate(object) end)
  end

  defp generate_data(:version, _type, _field), do: Schema.version()
  defp generate_data(:lang, _type, _field), do: "en"
  defp generate_data(:uuid, _type, _field), do: uuid()
  defp generate_data(:uid, _type, _field), do: uuid()
  defp generate_data(:type, _type, _field), do: word()
  defp generate_data(:name, _type, _field), do: String.capitalize(word())
  defp generate_data(:creator, _type, _field), do: full_name(2)
  defp generate_data(:accessor, _type, _field), do: full_name(2)
  defp generate_data(:modifier, _type, _field), do: full_name(2)
  defp generate_data(:full_name, _type, _field), do: full_name(2)
  defp generate_data(:shell, _type, _field), do: shell()
  defp generate_data(:timezone, _type, _field), do: timezone()

  defp generate_data(:event_time, _type, _field),
    do: time() |> DateTime.from_unix!(:microsecond) |> DateTime.to_iso8601()

  defp generate_data(:country, _type, _field), do: country()[:country_name]
  defp generate_data(:company_name, _type, _field), do: full_name(2)
  defp generate_data(:owner, _type, _field), do: full_name(2)
  defp generate_data(:ssid, _type, _field), do: word()
  defp generate_data(:labels, _type, _field), do: word()
  defp generate_data(:facility, _type, _field), do: facility()

  defp generate_data(key, "string_t", _field) do
    name = Atom.to_string(key)

    if String.ends_with?(name, "_uid") do
      uuid()
    else
      if String.ends_with?(name, "_ver") do
        version()
      else
        if String.ends_with?(name, "_code") do
          word()
        else
          sentence(3)
        end
      end
    end
  end

  defp generate_data(_name, "integer_t", field) do
    case field[:enum] do
      nil ->
        random(100)

      enum ->
        random_enum(enum)
    end
  end

  defp generate_data(_name, "timestamp_t", _field), do: time()
  defp generate_data(_name, "hostname_t", _field), do: domain()
  defp generate_data(_name, "ip_t", _field), do: ipv4()
  defp generate_data(_name, "subnet_t", _field), do: ipv4()
  defp generate_data(_name, "mac_t", _field), do: mac()
  defp generate_data(_name, "ipv4_t", _field), do: ipv4()
  defp generate_data(_name, "ipv6_t", _field), do: ipv6()
  defp generate_data(_name, "email_t", _field), do: email()
  defp generate_data(_name, "port_t", _field), do: random(65_536)
  defp generate_data(_name, "long_t", _field), do: random(65_536 * 65_536)
  defp generate_data(_name, "boolean_t", _field), do: random_boolean()
  defp generate_data(_name, "float_t", _field), do: random_float(100, 100)

  defp generate_data(name, "path_t", _field) do
    case name do
      :home_dir -> dir_file(random(3))
      :parent_dir -> dir_file(random(5))
      :path -> dir_file(5)
      _ -> file_name(0)
    end
  end

  defp generate_data(_name, _, _), do: word()

  def name() do
    Agent.get(__MODULE__, fn %Generator{names: {len, names}} -> random_word(len, names) end)
  end

  def names(n) do
    Agent.get(__MODULE__, fn %Generator{names: {len, names}} ->
      Enum.map(1..n, fn _ -> random_word(len, names) end)
    end)
  end

  def full_name(len) do
    names(len) |> Enum.join(" ")
  end

  def word() do
    Agent.get(__MODULE__, fn %Generator{words: {len, words}} -> random_word(len, words) end)
  end

  def words(n) do
    Agent.get(__MODULE__, fn %Generator{words: {len, words}} ->
      Enum.map(1..n, fn _ -> random_word(len, words) end)
    end)
  end

  def sentence(len) do
    words(len) |> Enum.join(" ")
  end

  def version() do
    n = random(3) + 1
    Enum.map(1..n, fn _ -> random(5) end) |> Enum.join(".")
  end

  def file_name(0) do
    word() <> file_ext()
  end

  def file_name(len) do
    name = "/" <> (words(len + 1) |> Path.join())
    name <> file_ext()
  end

  def dir_file(len) do
    "/" <> (words(len) |> Path.join())
  end

  def file_ext() do
    [ext, _] =
      Agent.get(__MODULE__, fn %Generator{files: {len, words}} ->
        random_word(len, words)
      end)

    ext
  end

  def blake2() do
    :crypto.hash(:blake2s, Schema.Generator.word()) |> Base.encode16()
  end

  def blake2b() do
    :crypto.hash(:blake2b, Schema.Generator.word()) |> Base.encode16()
  end

  def sha512() do
    :crypto.hash(:sha512, Schema.Generator.word()) |> Base.encode16()
  end

  def sha256() do
    :crypto.hash(:sha256, Schema.Generator.word()) |> Base.encode16()
  end

  def sha1() do
    :crypto.hash(:sha, Schema.Generator.word()) |> Base.encode16()
  end

  def md5() do
    :crypto.hash(:md5, Schema.Generator.word()) |> Base.encode16()
  end

  def shell() do
    Enum.random(["bash", "zsh", "fish", "sh"])
  end

  def ipv4() do
    Enum.map(1..4, fn _n -> random(256) end) |> Enum.join(".")
  end

  # 00:25:96:FF:FE:12:34:56
  def mac() do
    Enum.map(1..8, fn _n -> random(256) |> Integer.to_string(16) end)
    |> Enum.join(":")
  end

  # 2001:0000:3238:DFE1:0063:0000:0000:FEFB
  def ipv6() do
    Enum.map(1..8, fn _n ->
      random(65_536)
      |> Integer.to_string(16)
      |> String.pad_leading(4, "0")
    end)
    |> Enum.join(":")
  end

  def email() do
    [name(), "@", domain()] |> Enum.join()
  end

  def domain() do
    [word(), extension()] |> Enum.join(".")
  end

  def time() do
    :os.system_time(:millisecond)
  end

  def uuid() do
    UUID.uuid1()
  end

  def timezone() do
    (12 - random(24)) * 60
  end

  def random(n), do: :rand.uniform(n) - 1

  def random_boolean(), do: random(2) == 1

  def country() do
    Agent.get(__MODULE__, fn %Generator{countries: {len, names}} -> random_word(len, names) end)
  end

  def tactics() do
    Agent.get(__MODULE__, fn %Generator{tactics: {_len, tactics}} ->
      words = Map.keys(tactics)
      Enum.map(1..(random(3) + 1), fn _ -> Enum.random(words) end)
    end)
  end

  def technique() do
    Agent.get(__MODULE__, fn %Generator{techniques: {_len, techniques}} ->
      Enum.random(techniques)
    end)
  end

  def attack() do
    {uid, name} = technique()

    Map.new()
    |> Map.put(:tactics, tactics())
    |> Map.put(:technique_uid, uid)
    |> Map.put(:technique_name, name)
  end

  def location() do
    country = country()

    %{
      coordinates: coordinates(),
      continent: country.continent_name,
      country: country.two_letter_country_code,
      city: sentence(2) |> String.capitalize(),
      desc: country.country_name
    }
  end

  def coordinates() do
    [random_float(360, 180), random_float(180, 90)]
  end

  def random_float(n, r), do: Float.ceil(r - :rand.uniform_real() * n, 4)

  def fingerprint() do
    algorithm = random(7) - 1

    fingerprint =
      Map.new()
      |> Map.put(:algorithm_id, algorithm)

    value =
      case algorithm do
        -1 ->
          blake2()

        1 ->
          md5()

        2 ->
          sha1()

        3 ->
          sha256()

        _ ->
          blake2b()
      end

    fingerprint = Map.put(fingerprint, :value, value)

    if algorithm == -1 do
      Map.put(fingerprint, :algorithm, "blake2")
    else
      fingerprint
    end
  end

  defp random_enum(enum) do
    {name, _} = Enum.random(enum)
    name |> Atom.to_string() |> String.to_integer()
  end

  defp random_word(len, words) do
    :array.get(random(len), words)
  end

  def extension() do
    Enum.random([
      "aero",
      "arpa",
      "biz",
      "cat",
      "com",
      "coop",
      "edu",
      "firm",
      "gov",
      "info",
      "int",
      "jobs",
      "mil",
      "mobi",
      "museum",
      "name",
      "nato",
      "net",
      "org",
      "pro",
      "store",
      "travel",
      "web"
    ])
  end

  def facility() do
    Enum.random([
      "kern",
      "user",
      "mail",
      "daemon",
      "auth",
      "syslog",
      "lpr",
      "news",
      "uucp",
      "cron",
      "authpriv",
      "ftp",
      "local0",
      "local7"
    ])
  end

  defp read_data_file(filename) do
    list = File.stream!(filename) |> Stream.map(&String.trim_trailing/1) |> Enum.to_list()

    {length(list), :array.from_list(list)}
  end

  defp read_file_types(filename) do
    list =
      File.stream!(filename)
      |> Stream.map(&String.trim_trailing/1)
      |> Stream.map(fn s -> String.split(s, "\t") end)
      |> Stream.map(fn [ext, desc] -> [String.downcase(ext), desc] end)
      |> Enum.to_list()

    {length(list), :array.from_list(list)}
  end

  defp read_countries(filename) do
    list = File.read!(filename) |> Jason.decode!(keys: :atoms)

    {length(list), :array.from_list(list)}
  end

  defp read_json_file(filename) do
    map = File.read!(filename) |> Jason.decode!(keys: :atoms)

    {map_size(map), map}
  end

  def read_classes(path) do
    if File.dir?(path) do
      read_classes(nil, path, []) |> Enum.sort()
    else
      []
    end
  end

  defp read_classes(name, path, list) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, files} ->
          Enum.reduce(files, list, fn file, acc ->
            read_classes(file, Path.join(path, file), acc)
          end)

        error ->
          exit(error)
      end
    else
      if Path.extname(name) == ".json" do
        [{name, path} | list]
      else
        list
      end
    end
  end

  defp update_class_uid(file, uid) do
    data = File.read!(file) |> Jason.decode!()

    case Map.get(data, "uid") do
      nil ->
        uid

      c_uid ->
        IO.puts(
          "#{Integer.to_string(c_uid)} -> #{Integer.to_string(uid)} #{Map.get(data, "name")}"
        )

        Map.put(data, "uid", uid) |> write_json(file)
        uid + 1
    end
  end

  defp write_json(data, filename) do
    # if File.exists?(filename) do
    #   File.rename!(filename, filename <> ".bak")
    # end

    File.write!(filename, Jason.encode!(data, pretty: true))
  end
end
