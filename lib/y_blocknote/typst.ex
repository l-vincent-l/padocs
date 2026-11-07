defmodule YBlocknote.Typst do
  @moduledoc """
  A document written by the BlockNote editor (see `YBlocknote`) as
  [Typst](https://typst.app) markup, to compile into a PDF.

  The text of the document is never markup: each piece is a Typst string
  (`#"…"`), where only `\\` and `"` need escaping, so no character typed by a
  user (`#`, `*`, `$`, `/`…) can be read as formatting or code. Formatting and
  blocks are Typst functions around those strings (`#strong[…]`,
  `#heading(…)[…]`, `#table(…)`).

  Files (images, videos…) are not embedded: they become links to their URL,
  which compiling would otherwise have to download.
  """

  # BlockNote's default colors (COLORS_DEFAULT in @blocknote/core)
  @text_colors %{
    "gray" => "#9b9a97",
    "brown" => "#64473a",
    "red" => "#e03e3e",
    "orange" => "#d9730d",
    "yellow" => "#dfab01",
    "green" => "#4d6461",
    "blue" => "#0b6e99",
    "purple" => "#6940a5",
    "pink" => "#ad1a72"
  }

  @background_colors %{
    "gray" => "#ebeced",
    "brown" => "#e9e5e3",
    "red" => "#fbe4e4",
    "orange" => "#f6e9d9",
    "yellow" => "#fbf3db",
    "green" => "#ddedea",
    "blue" => "#ddebf1",
    "purple" => "#eae4f2",
    "pink" => "#f4dfeb"
  }

  @doc """
  The document as a Typst file: page and text settings, the title if given,
  then its blocks, nested ones under their parent.

  ## Options

    * `:title` - shown above the document, and set as the PDF's title
    * `:lang` - the language of the text, for hyphenation and quotes.
      Defaults to `"fr"`.
  """
  def to_typst(%Yex.XmlFragment{} = fragment, opts \\ []) do
    body =
      fragment
      |> Yex.XmlFragment.children()
      |> Enum.flat_map(&blocks/1)
      |> join_blocks()

    preamble(opts[:title], Keyword.get(opts, :lang, "fr")) <> body <> "\n"
  end

  @doc """
  `text` as a Typst string literal: shown as is, whatever its characters.
  """
  def string(text) do
    escaped =
      text
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"" <> escaped <> "\""
  end

  defp preamble(title, lang) do
    title_setting = if title in [nil, ""], do: "none", else: string(title)

    settings = [
      "#set document(title: #{title_setting})",
      ~s|#set page(paper: "a4", margin: 2.2cm)|,
      "#set text(lang: #{string(lang)}, size: 11pt)",
      "#show link: underline"
    ]

    heading =
      if title in [nil, ""],
        do: [],
        else: [~s|#block(below: 1.2em, text(size: 1.8em, weight: "bold", #{string(title)}))|]

    Enum.join(settings ++ heading, "\n") <> "\n\n"
  end

  # The blocks of a blockGroup, as `{kind, typst}`, kind telling which list
  # an item belongs to.
  defp blocks(%Yex.XmlElement{} = group) do
    group
    |> Yex.XmlElement.children()
    |> Enum.flat_map(&block_container/1)
  end

  defp blocks(_text), do: []

  # A blockContainer holds its block, then the blockGroup of its nested
  # blocks if it has some. A block without content leaves its nested blocks
  # in its place.
  defp block_container(container) do
    [block | nested] = container |> Yex.XmlElement.children() |> Enum.to_list()
    children = nested |> Enum.flat_map(&blocks/1)

    case block(Yex.XmlElement.get_tag(block), block) do
      nil -> children
      {kind, typst} -> [{kind, nest(typst, join_blocks(children), kind)}]
    end
  end

  defp block("heading", block) do
    level = block |> Yex.XmlElement.get_attribute("level") |> heading_level()
    with_text(block, &{:block, "#heading(level: #{level})[#{&1}]"})
  end

  defp block("bulletListItem", block), do: with_text(block, &{:list, "- " <> &1})
  defp block("toggleListItem", block), do: with_text(block, &{:list, "- " <> &1})
  defp block("numberedListItem", block), do: with_text(block, &{:list, "+ " <> &1})

  defp block("checkListItem", block) do
    box = if checked?(block), do: "☑ ", else: "☐ "
    with_text(block, &{:list, "- #" <> string(box) <> &1})
  end

  defp block("quote", block), do: with_text(block, &{:block, "#quote(block: true)[#{&1}]"})

  defp block("codeBlock", block) do
    lang =
      case Yex.XmlElement.get_attribute(block, "language") do
        language when language in [nil, "", "text"] -> ""
        language -> "lang: #{string(language)}, "
      end

    {:block, "#raw(block: true, #{lang}#{string(plain_text(block))})"}
  end

  defp block("table", block), do: {:block, table(block)}
  defp block("divider", _block), do: {:block, "#line(length: 100%, stroke: 0.5pt + gray)"}

  defp block(tag, block) when tag in ["image", "video", "audio", "file"] do
    url = Yex.XmlElement.get_attribute(block, "url")

    name =
      Enum.find(
        [
          Yex.XmlElement.get_attribute(block, "caption"),
          Yex.XmlElement.get_attribute(block, "name"),
          url
        ],
        &(&1 not in [nil, ""])
      )

    label = %{"image" => "Image", "video" => "Vidéo", "audio" => "Son", "file" => "Fichier"}

    if url in [nil, ""],
      do: nil,
      else: {:block, "#link(#{string(url)})[#" <> string("#{label[tag]} : #{name}") <> "]"}
  end

  # Paragraphs, and blocks unknown to this module, keep their text, aligned
  # as in the editor.
  defp block(_tag, block) do
    with_text(block, fn text ->
      case Yex.XmlElement.get_attribute(block, "textAlignment") do
        "center" -> {:block, "#align(center)[#{text}]"}
        "right" -> {:block, "#align(right)[#{text}]"}
        "justify" -> {:block, "#par(justify: true)[#{text}]"}
        _ -> {:block, text}
      end
    end)
  end

  # The block made by `fun` from the formatted text of `block`; none when it
  # has no text.
  defp with_text(block, fun) do
    if String.trim(plain_text(block)) == "", do: nil, else: fun.(inline(block))
  end

  defp checked?(block), do: to_string(Yex.XmlElement.get_attribute(block, "checked")) == "true"

  # Nested blocks: under a list item, indented in the same item; under
  # another block, in an indented block after it.
  defp nest(typst, "", _kind), do: typst

  defp nest(typst, children, :list), do: typst <> "\n" <> indent(children, "  ")

  defp nest(typst, children, :block),
    do: typst <> "\n\n#pad(left: 1.5em)[\n" <> indent(children, "  ") <> "\n]"

  defp indent(typst, indent) do
    typst
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> indent <> line
    end)
  end

  # Items of the same list are on consecutive lines; other blocks are
  # separated by a blank line.
  defp join_blocks([]), do: ""

  defp join_blocks([{_kind, first} | _] = blocks) do
    blocks
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map_join(fn [{previous, _}, {kind, typst}] ->
      if previous == :list and kind == :list, do: "\n" <> typst, else: "\n\n" <> typst
    end)
    |> then(&(first <> &1))
  end

  # The rows of a table, the first one as its header; each cell holds its
  # text in a tableParagraph.
  defp table(table) do
    rows =
      for row <- Yex.XmlElement.children(table) do
        for cell <- Yex.XmlElement.children(row) do
          "[" <> (cell |> Yex.XmlElement.children() |> Enum.map_join(" ", &inline/1)) <> "]"
        end
      end

    case rows do
      [] ->
        ""

      [header | body] ->
        columns = rows |> Enum.map(&length/1) |> Enum.max()

        cells =
          ["table.header(" <> Enum.join(header, ", ") <> ")" | List.flatten(body)]
          |> Enum.join(",\n  ")

        "#table(\n  columns: #{columns},\n  #{cells}\n)"
    end
  end

  # BlockNote stores the level as a number, which y_ex reads as a float (or an
  # integer before y_ex 0.13); older documents may hold it as text.
  defp heading_level(level) when is_integer(level), do: clamp_level(level)
  defp heading_level(level) when is_float(level), do: clamp_level(trunc(level))

  defp heading_level(level) when is_binary(level) do
    case Integer.parse(level) do
      {level, _rest} -> clamp_level(level)
      :error -> 1
    end
  end

  defp heading_level(_level), do: 1

  defp clamp_level(level), do: level |> max(1) |> min(6)

  # The text of an element, formatted.
  defp inline(%Yex.XmlElement{} = element) do
    element
    |> Yex.XmlElement.children()
    |> Enum.map_join(&inline/1)
  end

  defp inline(%Yex.XmlText{} = text) do
    for %{insert: insert} = part when is_binary(insert) <- Yex.XmlText.to_delta(text),
        into: "",
        do: format(insert, Map.get(part, :attributes, %{}))
  end

  defp plain_text(element) do
    for %Yex.XmlText{} = text <- Yex.XmlElement.children(element), into: "", do: xml_text(text)
  end

  # A piece of text with its marks, applied inside out. Line breaks within a
  # block (shift+enter) are explicit; code keeps them.
  defp format(text, attributes) do
    core =
      if mark?(attributes, "code") do
        "#raw(#{string(text)})"
      else
        text
        |> String.split("\n")
        |> Enum.map(&if(&1 == "", do: "", else: "#" <> string(&1)))
        |> Enum.join("#linebreak()")
      end

    [
      {"bold", &"#strong[#{&1}]"},
      {"italic", &"#emph[#{&1}]"},
      {"underline", &"#underline[#{&1}]"},
      {"strike", &"#strike[#{&1}]"}
    ]
    |> Enum.reduce(core, fn {mark, wrap}, core ->
      if mark?(attributes, mark), do: wrap.(core), else: core
    end)
    |> color(@text_colors[color_name(attributes["textColor"])], "text")
    |> color(@background_colors[color_name(attributes["backgroundColor"])], "highlight")
    |> link(attributes["link"])
  end

  defp mark?(attributes, mark), do: attributes[mark] not in [nil, false]

  # A color mark holds its name, as `{stringValue: name}` (or the name itself).
  defp color_name(%{"stringValue" => name}), do: name
  defp color_name(name) when is_binary(name), do: name
  defp color_name(_), do: nil

  defp color(typst, nil, _function), do: typst

  defp color(typst, hex, "text"), do: ~s|#text(fill: rgb("#{hex}"))[#{typst}]|
  defp color(typst, hex, "highlight"), do: ~s|#highlight(fill: rgb("#{hex}"))[#{typst}]|

  defp link(typst, %{"href" => href}) when is_binary(href),
    do: "#link(#{string(href)})[#{typst}]"

  defp link(typst, _), do: typst

  # Plain text, without formatting or embeds (mentions, images...).
  defp xml_text(xml_text) do
    for %{insert: insert} when is_binary(insert) <- Yex.XmlText.to_delta(xml_text),
        into: "",
        do: insert
  end
end
