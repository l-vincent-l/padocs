defmodule YexBlockNote do
  @moduledoc """
  Reads a document written by the BlockNote editor in a `Yex.XmlFragment`, as
  blocks, text, Markdown or Typst.

  The fragment's name is chosen by the application when it sets up BlockNote's
  collaboration, so the functions take the fragment itself, e.g.
  `Yex.Doc.get_xml_fragment(doc, "document-store")`. They also take the
  blocks returned by `to_blocks/1`, to read a fragment once for several
  renderings.

  ## Blocks

  BlockNote's y-prosemirror binding stores nested `blockGroup` >
  `blockContainer` > block elements (`paragraph`, `heading`...). The blocks
  drop that structure and keep, as BlockNote's own document does, one map per
  block:

      %{
        type: "heading",
        props: %{"level" => 2, "textAlignment" => "left", ...},
        content: [%{text: "Title", styles: %{"bold" => %{}}}],
        children: [...]
      }

    * `props` - the attributes of the block, as stored, except `"level"`,
      always an integer, and `"checked"`, always a boolean
    * `content` - the inline content of the block, a list of
      `%{text: text, styles: styles}` with the marks of the text (`"bold"`,
      `"link"`, `"textColor"`...), and of `%{type: tag, props: props,
      content: inline}` for inline elements such as mentions. For a table,
      `%{rows: rows}`, each row being a list of cells, each cell the inline
      content of its paragraphs.
    * `children` - the nested blocks
  """

  alias YexBlockNote.{Blocks, Markdown, Text, Typst}

  @doc "The blocks of the document, nested ones under their parent."
  def to_blocks(%Yex.XmlFragment{} = fragment), do: Blocks.read(fragment)

  @doc """
  The document is empty when it has no text and only holds paragraphs: any
  other block (image, table, divider...) or inline element counts as content.
  """
  def empty?(document), do: document |> blocks() |> Text.empty?()

  @doc """
  The text of the document, without formatting: one trimmed line per block
  holding text (per cell for tables), nested blocks included, in document
  order. Blank lines are dropped.
  """
  def to_text(document), do: document |> blocks() |> Text.to_text()

  @doc """
  The document as Markdown, one block after the other, nested blocks indented
  under their parent. Text colors, alignment and underline have no Markdown
  equivalent and are dropped; so are blocks without text, such as empty
  paragraphs.
  """
  def to_markdown(document), do: document |> blocks() |> Markdown.to_markdown()

  @doc """
  The document as [Typst](https://typst.app) markup, to compile into a PDF:
  page and text settings, the title if given, then its blocks, nested ones
  under their parent. No text typed by a user can be read as Typst markup or
  code. Files (images, videos…) are not embedded: they become links to their
  URL, which compiling would otherwise have to download.

  ## Options

    * `:title` - shown above the document, and set as the PDF's title
    * `:lang` - the language of the text, for hyphenation and quotes.
      Defaults to `"fr"`.
  """
  def to_typst(document, opts \\ []), do: document |> blocks() |> Typst.to_typst(opts)

  defp blocks(%Yex.XmlFragment{} = fragment), do: Blocks.read(fragment)
  defp blocks(blocks) when is_list(blocks), do: blocks
end
