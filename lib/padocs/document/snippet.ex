defmodule Padocs.Document.Snippet do
  @moduledoc """
  Fragment of a text around the words of a search query, these words marked,
  to show where a document matches.

  Tantivy's `SnippetGenerator` (`TantivyEx.Searcher.snippet/5`) picks the
  fragment and finds the words, with the field's tokenizer, so that the marked
  words are the ones the search found. This module turns its result into
  segments to display.
  """

  @typedoc "A part of the fragment: plain text, or a word of the query."
  @type segment :: {:text | :match, String.t()}

  @doc """
  The segments of a snippet of `text`: `fragment`, a part of `text`, split at
  the byte ranges `highlighted` of the matched words. "…" marks where `text` is
  cut, and line breaks become spaces. `nil` when nothing matched (an empty
  fragment).
  """
  @spec segments(String.t(), %{fragment: String.t(), highlighted: [{integer(), integer()}]}) ::
          [segment()] | nil
  def segments(_text, %{fragment: ""}), do: nil

  def segments(text, %{fragment: fragment, highlighted: highlighted}) do
    # where the fragment is in the text, to know whether the text is cut
    {from, length} =
      case :binary.match(text, fragment) do
        :nomatch -> {0, byte_size(text)}
        found -> found
      end

    {segments, position} =
      Enum.flat_map_reduce(highlighted, 0, fn {start, stop}, position ->
        {[
           {:text, binary_part(fragment, position, start - position)},
           {:match, binary_part(fragment, start, stop - start)}
         ], stop}
      end)

    ([{:text, if(from > 0, do: "…", else: "")} | segments] ++
       [
         {:text, binary_part(fragment, position, byte_size(fragment) - position)},
         {:text, if(from + length < byte_size(text), do: "…", else: "")}
       ])
    |> Enum.map(fn
      {:text, text} -> {:text, String.replace(text, ~r/\s+/u, " ")}
      match -> match
    end)
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      [{:text, _} | _] = texts -> [{:text, Enum.map_join(texts, &elem(&1, 1))}]
      matches -> matches
    end)
    |> Enum.reject(&(&1 == {:text, ""}))
  end
end
