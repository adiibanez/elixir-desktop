defmodule Desktop.Utils do
  require Logger

  @doc """
  Removes HTML-style comments (<!-- ... -->) from a string, handling potential errors.
  """
  def strip_comments(input) do
    if String.contains?(input, "<!--") do
      regex = ~r/<!--.*?-->/s

      case Regex.replace(regex, input, fn _ -> "" end) do
        {:ok, result} ->
          {:ok, result}

        {:error, _} ->
          Logger.debug("#{__MODULE__} strip_comments error")
          {:ok, input}

        _ ->
          {:ok, input}
      end
    else
      {:ok, input}
    end
  end
end
