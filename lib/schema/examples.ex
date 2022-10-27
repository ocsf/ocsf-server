defmodule Schema.Examples do
  @moduledoc """
    Creates the examples repo structure.
  """

  @readme_file "README.md"

  @doc """
  Creates the README files
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
end
