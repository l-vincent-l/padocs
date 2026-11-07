defmodule Textexp.Document.Body do
  @moduledoc """
  The body of a document: the XmlFragment written by the BlockNote editor
  (blocknote.tsx), read with `YBlocknote`.
  """

  # The fragment the editor syncs (see withCollaboration in blocknote.tsx)
  @fragment "document-store"
  @excerpt_lines 3
  @excerpt_length 280

  @doc "See `YBlocknote.empty?/1`."
  def empty?(doc), do: doc |> fragment() |> YBlocknote.empty?()

  @doc """
  The first non-blank lines of the body, one per block, joined with newlines,
  to preview the document. `nil` when the body has no text.
  """
  def excerpt(doc) do
    doc
    |> fragment()
    |> YBlocknote.text_lines()
    |> Enum.take(@excerpt_lines)
    |> Enum.join("\n")
    |> String.slice(0, @excerpt_length)
    |> case do
      "" -> nil
      excerpt -> excerpt
    end
  end

  @doc "See `YBlocknote.to_text/1`."
  def text(doc), do: doc |> fragment() |> YBlocknote.to_text()

  @doc "See `YBlocknote.to_markdown/1`."
  def to_markdown(doc), do: doc |> fragment() |> YBlocknote.to_markdown()

  @doc "See `YBlocknote.Typst.to_typst/2`."
  def to_typst(doc, opts \\ []), do: doc |> fragment() |> YBlocknote.Typst.to_typst(opts)

  defp fragment(doc), do: Yex.Doc.get_xml_fragment(doc, @fragment)
end
