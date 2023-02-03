# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
defmodule Schema.Examples do
  @moduledoc """
    The OCSF examples repo helper functions.
  """
  require Logger

  @readme_file "README.md"
  @glob_pattern "**/*.json"

  @doc """
    Finds OCSF JSON example files for the given class uid.
  """
  @spec find(number()) :: list()
  def find(uid) do
    cache_get(uid)
  end

  @doc """
  Creates the README files.
  """
  @spec create_readme(binary()) :: any()
  def create_readme(path) do
    if File.dir?(path) do
      case File.ls(path) do
        {:ok, files} ->
          Enum.each(files, fn file ->
            path = Path.join(path, file)

            if File.dir?(path) and !String.starts_with?(file, ".") do
              create_readme_file(file, path)
              create_readme(path)
            end
          end)

        error ->
          exit(error)
      end
    end
  end

  defp create_readme_file(name, path) do
    file = Path.join(path, @readme_file)

    case File.exists?(file) do
      false ->
        case File.write(file, "# #{name} Examples") do
          :ok ->
            IO.puts("created README file  : #{file}")

          {:error, reason} ->
            IO.puts("unable to create file: #{file}. Error: #{reason}")
        end

      true ->
        IO.puts("file already exists  : #{file} ")
    end
  end

  def fine_uniq_verbs(filename) do
    File.stream!(filename)
    |> Stream.map(fn name ->
      String.trim_trailing(name) |> String.split(~r/(?=[A-Z])/) |> Enum.at(1)
    end)
    |> Stream.uniq()
    |> Enum.each(fn n -> IO.puts(n) end)
  end

  # ETS cache for the json example links
  def init_cache() do
    name = __MODULE__
    home = examples_dir()
    repo = Application.get_env(:schema_server, __MODULE__) |> Keyword.get(:repo)

    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:duplicate_bag, :protected, :named_table])
        # build the example links cache
        build_cache(repo, home)

      _ ->
        Logger.error("ETS table with name #{name} already exists.")
    end
  end

  defp examples_dir() do
    (Application.get_env(:schema_server, __MODULE__)
    |> Keyword.get(:home) || "../examples")
    |> Path.absname()
    |> Path.expand()
  end

  defp build_cache(nil, _path) do
    Logger.warn("The EXAMPLES_REPO path is not configured.")
  end
  
  defp build_cache(repo, path) do
    if File.dir?(path) do
      Logger.info("Scanning #{path} directory for JSON data files")

      Path.join(path, @glob_pattern)
      |> Path.wildcard()
      |> Stream.map(fn name -> {name, parse_json(name)} end)
      |> Stream.filter(fn {_name, data} -> is_ocsf_data?(data) end)
      |> Stream.map(fn item -> reduce(repo, path, item) end)
      |> Enum.each(&cache_put/1)
    else
      Logger.warn("#{path} is not a directory")
    end
  end

  defp parse_json(name) do
    File.read!(name) |> Jason.decode!()
  end

  defp is_ocsf_data?(data) do
    is_map(data) and Map.has_key?(data, "class_uid")
  end

  defp reduce(repo, path, {name, data}) do
    dir = Path.dirname(name)
    url = Path.join(repo, String.trim_leading(dir, path)) |> URI.encode()

    {
      Map.get(data, "class_uid"),
      read_dossier(dir),
      url
    }
  end

  defp read_dossier(dir) do
    path = Path.join(dir, @readme_file)

    case File.open(path, [:read]) do
      {:ok, file} ->
        try do
          IO.read(file, :line) |> example_name()
        after
          File.close(file)
        end

      _ ->
        "Noname"
    end
  end

  defp example_name(line) do
    case String.split(line, ": ") do
      [_, name] -> String.trim(name)
      _ -> "Noname"
    end
  end

  defp cache_put(data) do
    :ets.insert(__MODULE__, data)
    data
  end

  defp cache_get(uid) do
    :ets.lookup(__MODULE__, uid)
  end
end
