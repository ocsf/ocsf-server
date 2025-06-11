defmodule Schema.CompilationTest do
  use ExUnit.Case

  test ": Schema compilation should not have any errors" do
    # Get all error messages from the Logger
    log_path = "log/test.log"

    # Ensure the log directory exists
    File.mkdir_p!(Path.dirname(log_path))

    # Read the log file if it exists
    log_content = if File.exists?(log_path) do
      File.read!(log_path)
    else
      ""
    end

    # Check for error messages in the log
    error_lines = log_content
      |> String.split("\n")
      |> Enum.filter(fn line ->
        String.contains?(line, "[error]")
      end)

    # If there are any error lines, fail the test with those errors
    if length(error_lines) > 0 do
      formatted_errors = error_lines
        |> Enum.map(fn line ->
          # Extract just the error message part
          case Regex.run(~r/\[error\].*?/, line) do
            [_, error_msg] -> "  - #{error_msg}"
            _ -> "  - #{line}"
          end
        end)
        |> Enum.join("\n")

      flunk("Schema compilation errors found:\n#{formatted_errors}")
    end

    assert true, "Schema compilation passed with no errors"
  end
end
