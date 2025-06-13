defmodule Schema.CompilationTest do
  use ExUnit.Case

  test "Schema compilation should not have any errors" do
    # Find the most recent test log file
    log_dir = "log"

    # Ensure the log directory exists
    File.mkdir_p!(log_dir)

    # Clean up old test log files to prevent sprawl (keep only the most recent 3)
    case File.ls(log_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.starts_with?(&1, "test_"))
        |> Enum.filter(&String.ends_with?(&1, ".log"))
        |> Enum.sort(:desc)
        |> Enum.drop(3)  # Keep the 3 most recent, delete the rest
        |> Enum.each(fn old_file ->
          File.rm(Path.join(log_dir, old_file))
        end)
      {:error, _} -> :ok
    end

    # Find all test log files and get the most recent one
    {:ok, files} = File.ls(log_dir)

    log_path = files
      |> Enum.filter(&String.starts_with?(&1, "test_"))
      |> Enum.filter(&String.ends_with?(&1, ".log"))
      |> Enum.sort(:desc)
      |> List.first()
      |> then(fn filename -> Path.join(log_dir, filename) end)

    # Read the log file if it exists
    log_content = case File.read(log_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end

    # Check for error messages in the log
    error_lines = log_content
      |> String.split("\n")
      |> Enum.filter(fn line ->
        String.contains?(line, "[error]") and String.trim(line) != ""
      end)

    # If there are any error lines, fail the test with those errors
    if length(error_lines) > 0 do
      formatted_errors = error_lines
        |> Enum.map(fn line ->
          # Extract just the error message part
          case Regex.run(~r/\[error\]\s*(.*)/, line) do
            [_full_match, error_msg] -> "  - #{String.trim(error_msg)}"
            _ -> "  - #{line}"
          end
        end)
        |> Enum.join("\n")

      flunk("Schema compilation errors found:\n#{formatted_errors}")
    end

    assert true, "Schema compilation passed with no errors"
  end
end
