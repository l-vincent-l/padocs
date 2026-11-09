defmodule YexBlockNote.Markdown do
  @moduledoc false

  alias YexBlockNote.Text

  def to_markdown(blocks), do: blocks |> markdown_blocks() |> join_blocks()

  # The blocks as `{kind, markdown}` where kind tells whether consecutive
  # blocks belong to the same list.
  defp markdown_blocks(blocks) do
    {blocks, _number} = Enum.flat_map_reduce(blocks, 0, &block_with_children/2)
    blocks
  end

  # `number` is the number of the previous item of a numbered list, 0 if the
  # previous block is not one. A block without content leaves its nested
  # blocks in its place.
  defp block_with_children(%{type: type, children: children} = block, number) do
    number = if type == "numberedListItem", do: number + 1, else: 0

    case block(type, block, number) do
      nil ->
        {markdown_blocks(children), number}

      {kind, markdown} ->
        nested = children |> markdown_blocks() |> join_blocks()
        {[{kind, nest(markdown, nested, kind)}], number}
    end
  end

  defp block("heading", block, _number) do
    text_block(:block, String.duplicate("#", block.props["level"] || 1) <> " ", block)
  end

  defp block("bulletListItem", block, _number), do: text_block(:list, "- ", block)
  defp block("toggleListItem", block, _number), do: text_block(:list, "- ", block)
  defp block("numberedListItem", block, number), do: text_block(:list, "#{number}. ", block)

  defp block("checkListItem", block, _number) do
    text_block(:list, if(block.props["checked"], do: "- [x] ", else: "- [ ] "), block)
  end

  defp block("quote", block, _number) do
    case inline(block.content) do
      "" -> nil
      text -> {:block, text |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))}
    end
  end

  defp block("codeBlock", block, _number) do
    language = block.props["language"] || ""
    {:block, "```#{language}\n#{Text.inline(block.content)}\n```"}
  end

  defp block("table", block, _number), do: {:block, table(block.content.rows)}
  defp block("divider", _block, _number), do: {:block, "---"}

  defp block(type, %{props: props}, _number) when type in ["image", "video", "audio", "file"] do
    url = props["url"]
    name = props["caption"] || props["name"]
    name = if name in [nil, ""], do: url, else: name

    cond do
      url in [nil, ""] -> nil
      type == "image" -> {:block, "![#{name}](#{url})"}
      true -> {:block, "[#{name}](#{url})"}
    end
  end

  # Paragraphs, and blocks unknown to this module, keep their text.
  defp block(_type, block, _number), do: text_block(:block, "", block)

  defp text_block(kind, prefix, %{content: content}) when is_list(content) do
    case inline(content) do
      "" -> nil
      text -> {kind, prefix <> text}
    end
  end

  defp text_block(_kind, _prefix, _block), do: nil

  # Nested blocks go under their parent, indented to the parent's text so that
  # they stay in the same list item.
  defp nest(markdown, "", _kind), do: markdown

  defp nest(markdown, children, kind) do
    indent = if kind == :list, do: list_marker_width(markdown), else: 2
    separator = if kind == :list, do: "\n", else: "\n\n"
    markdown <> separator <> indent(children, String.duplicate(" ", indent))
  end

  defp list_marker_width(markdown) do
    [marker] = Regex.run(~r/^(?:- \[[ x]\] |- |\d+\. )/, markdown)
    String.length(marker)
  end

  defp indent(markdown, indent) do
    markdown
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
    |> Enum.map_join(fn [{previous, _}, {kind, markdown}] ->
      if previous == :list and kind == :list, do: "\n" <> markdown, else: "\n\n" <> markdown
    end)
    |> then(&(first <> &1))
  end

  # The rows of a table, the first one taken as header.
  defp table([]), do: ""

  defp table(rows) do
    [header | body] =
      for row <- rows do
        for cell <- row do
          cell |> inline() |> String.replace("|", "\\|") |> String.replace("\n", " ")
        end
      end

    separator = Enum.map(header, fn _ -> "---" end)
    Enum.map_join([header, separator | body], "\n", &("| " <> Enum.join(&1, " | ") <> " |"))
  end

  # Inline content with its formatting as Markdown.
  defp inline(content), do: content |> Enum.map_join(&inline_part/1) |> String.trim()

  defp inline_part(%{text: text, styles: styles}), do: format(text, styles)
  defp inline_part(%{content: content}), do: Enum.map_join(content, &inline_part/1)

  # Marks are applied inside out; the spaces around a formatted part are kept
  # outside of its markers, which Markdown would not recognize otherwise.
  defp format(text, styles) do
    case Regex.run(~r/^(\s*)(.*?)(\s*)$/s, text) do
      [_, leading, "", trailing] ->
        leading <> trailing

      [_, leading, core, trailing] ->
        core =
          [
            {"code", &"`#{&1}`"},
            {"bold", &"**#{&1}**"},
            {"italic", &"_#{&1}_"},
            {"strike", &"~~#{&1}~~"}
          ]
          |> Enum.reduce(core, fn {mark, wrap}, core ->
            if mark?(styles, mark), do: wrap.(core), else: core
          end)
          |> link(styles["link"])

        leading <> core <> trailing
    end
  end

  defp mark?(styles, mark), do: styles[mark] not in [nil, false]

  defp link(text, %{"href" => href}) when is_binary(href), do: "[#{text}](#{href})"
  defp link(text, _), do: text
end
