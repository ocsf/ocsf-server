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

  @doc """
  Generate an event intance using the given class.
  """
  def event(nil), do: nil

  def event(class) do
    Logger.info("class: #{inspect(class.name)}")

    data = generate(class)
    uid = data.class_id * 1000 + (data.outcome_id &&& 0xFFFF)

    Map.put(data, :event_uid, uid)
  end

  def generate(class) do
    case class.type do
      "location" ->
        location()

      "fingerprint" ->
        fingerprint()

      "attack" ->
        attack()

      _ ->
        Enum.reduce(class.attributes, Map.new(), fn {name, field} = attribute, map ->
          if field[:is_array] == true do
            Map.put(map, name, generate_array(attribute))
          else
            case field[:type] do
              "object_t" ->
                Map.put(map, name, generate_object(attribute))

              nil ->
                Logger.error("Missing class: #{name}")
                map

              _other ->
                generate(attribute, map)
            end
          end
        end)
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

  defp generate_array({:groups, _field}) do
    words(5)
  end

  defp generate_array({name, field} = attribute) do
    n = random(5)

    case field[:type] do
      "object_t" ->
        generate_objects(n, attribute)

      type ->
        Enum.map(1..n, fn _ -> data(name, type, field) end)
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

  defp generate({:version, _field}, map), do: Map.put(map, :version, Schema.version())
  defp generate({:lang, _field}, map), do: Map.put(map, :lang, "en")
  defp generate({:uuid, _field}, map), do: Map.put(map, :uuid, uuid())
  defp generate({:uid, _field}, map), do: Map.put(map, :uid, uuid())
  defp generate({:name, _field}, map), do: Map.put(map, :name, String.capitalize(word()))
  defp generate({:creator, _field}, map), do: Map.put(map, :creator, full_name(2))
  defp generate({:accessor, _field}, map), do: Map.put(map, :accessor, full_name(2))
  defp generate({:modifier, _field}, map), do: Map.put(map, :modifier, full_name(2))
  defp generate({:full_name, _field}, map), do: Map.put(map, :full_name, full_name(2))
  defp generate({:shell, _field}, map), do: Map.put(map, :shell, shell())
  defp generate({:timezone, _field}, map), do: Map.put(map, :timezone, timezone())
  defp generate({:country, _field}, map), do: Map.put(map, :country, country()[:country_name])
  defp generate({:company_name, _field}, map), do: Map.put(map, :company_name, full_name(2))
  defp generate({:owner, _field}, map), do: Map.put(map, :owner, full_name(2))
  defp generate({:facility, _field}, map), do: Map.put(map, :facility, facility())
  defp generate({:unmapped, _field}, map), do: map
  defp generate({:raw_data, _field}, map), do: map

  defp generate({name, field}, map) do
    requirement = field[:requirement]

    #  Generate all required and 20% of the optional fields
    if requirement == "required" or random(100) > 90 do
      Map.put(map, name, data(name, field.type, field))
    else
      map
    end
  end

  defp data(key, "string_t", _field) do
    name = Atom.to_string(key)

    if String.ends_with?(name, "_uid") or String.ends_with?(name, "_id") do
      uuid()
    else
      sentence(3)
    end
  end

  defp data(_name, "timestamp_t", _field), do: time()
  defp data(_name, "hostname_t", _field), do: domain()
  defp data(_name, "ip_t", _field), do: ipv4()
  defp data(_name, "subnet_t", _field), do: ipv4()
  defp data(_name, "mac_t", _field), do: mac()
  defp data(_name, "ipv4_t", _field), do: ipv4()
  defp data(_name, "ipv6_t", _field), do: ipv6()
  defp data(_name, "email_t", _field), do: email()
  defp data(_name, "port_t", _field), do: random(65536)
  defp data(_name, "long_t", _field), do: random(65536 * 65536)
  defp data(_name, "boolean_t", _field), do: random_boolean()
  defp data(_name, "float_t", _field), do: random_float(100, 100)

  defp data(name, "path_t", _field) do
    case name do
      :home_dir -> dir_file(random(3))
      :parent_dir -> dir_file(random(5))
      :path -> dir_file(5)
      _ -> file_name(0)
    end
  end

  defp data(_name, "integer_t", field) do
    case field[:enum] do
      nil ->
        random(100)

      enum ->
        random(enum)
    end
  end

  defp data(_name, _, _), do: word()

  def init() do
    dir = Application.app_dir(:schema_server, @data_dir)

    Logger.info("Loading data files: #{dir}")

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
      random(65536)
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

  def random_boolean() do
    random(2) == 1
  end

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

  def random(n) when is_integer(n), do: :rand.uniform(n) - 1

  def random(enum) do
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
end
