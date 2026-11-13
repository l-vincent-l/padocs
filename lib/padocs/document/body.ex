defmodule Padocs.Document.Body do
  @moduledoc """
  The body of a document: the XmlFragment written by the BlockNote editor
  (blocknote.tsx), read with `YexBlockNote`.
  """

  # The fragment the editor syncs (see withCollaboration in blocknote.tsx)
  @fragment "document-store"
  @excerpt_lines 3
  @excerpt_length 280

  @doc "See `YexBlockNote.empty?/1`."
  def empty?(doc), do: doc |> fragment() |> YexBlockNote.empty?()

  @doc """
  The first non-blank lines of the body, one per block, joined with newlines,
  to preview the document. `nil` when the body has no text.
  """
  def excerpt(doc) do
    doc
    |> fragment()
    |> YexBlockNote.to_text()
    |> String.split("\n")
    |> Enum.take(@excerpt_lines)
    |> Enum.join("\n")
    |> String.slice(0, @excerpt_length)
    |> case do
      "" -> nil
      excerpt -> excerpt
    end
  end

  @doc "See `YexBlockNote.to_text/1`."
  def text(doc), do: doc |> fragment() |> YexBlockNote.to_text()

  @doc "See `YexBlockNote.to_markdown/1`."
  def to_markdown(doc), do: doc |> fragment() |> YexBlockNote.to_markdown()

  @doc "See `YexBlockNote.to_typst/2`."
  def to_typst(doc, opts \\ []), do: doc |> fragment() |> YexBlockNote.to_typst(opts)

  defp fragment(doc), do: Yex.Doc.get_xml_fragment(doc, @fragment)
end
