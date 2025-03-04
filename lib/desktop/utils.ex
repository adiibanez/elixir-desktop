defmodule Desktop.Utils do
  require Logger

  @doc """
  Removes HTML-style comments (<!-- ... -->) from a string, handling potential errors.
  """
  def strip_comments(input) do
    if String.contains(input, "<!--") do
      regex = ~r/<!--.*?-->/s

      case Regex.replace(regex, input, fn _ -> "" end) do
        {:ok, result} ->
          result

        {:error, _} ->
          Logger.debug("#{__MODULE__} strip_comments error")
          input

        _ ->
          input
      end
    else
      input
    end
  end
end
