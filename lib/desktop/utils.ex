defmodule Desktop.Utils do
  require Logger

  @doc """
  Removes HTML-style comments (<!-- ... -->) from a string or a list of strings, handling potential errors.
  """

  # Handle a single string
  def strip_comments(input) when is_binary(input) do
    IO.inspect(input, label: "strip_comments (string)")

    if String.contains?(input, "<!--") do
      regex = ~r/<!--.*?-->/s

      case Regex.replace(regex, input, fn _ -> "" end) do
        result when is_binary(result) -> #It can return a string directly without "OK" response.
          Logger.debug("#{__MODULE__} strip_comments replaced #{result}")
          result  # Return the stripped string directly
        {:error, error} ->
          Logger.error("#{__MODULE__} strip_comments error: #{inspect(error)}")
          input  # Return the original input string on error

      end
    else
      input  # Return the original input string if no comments are present
    end
  end

  # Handle a list of strings
  def strip_comments(input) when is_list(input) do
    IO.inspect(input, label: "strip_comments (list)")

    # Use Enum.map to process each string in the list and strip comments
    Enum.map(input, fn item ->
      strip_comments(item)  # Recursively call strip_comments to handle individual strings
    end)
  end

  # Catch all clause, if the object is of incorrect type, then return it.
  def strip_comments(input) do
    Logger.warning("#{__MODULE__} strip_comments received unsupported input type: #{inspect(input)}")
    input
  end
end
