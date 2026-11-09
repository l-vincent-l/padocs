defmodule YexBlockNote.Text do
  @moduledoc false

  def empty?(blocks), do: Enum.all?(blocks, &empty_block?/1)

  defp empty_block?(%{type: "paragraph", content: content, children: children}) do
    Enum.all?(content, &match?(%{text: _}, &1)) and String.trim(inline(content)) == "" and
      empty?(children)
  end

  defp empty_block?(_block), do: false

  def to_text(blocks) do
    blocks
    |> Enum.flat_map(&lines/1)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp lines(%{content: %{rows: rows}, children: children}) do
    for(row <- rows, cell <- row, do: inline(cell)) ++ Enum.flat_map(children, &lines/1)
  end

  defp lines(%{content: content, children: children}),
    do: [inline(content) | Enum.flat_map(children, &lines/1)]

  # The text of inline content, without formatting, inline elements included.
  def inline(content) when is_list(content) do
    Enum.map_join(content, fn
      %{text: text} -> text
      %{content: content} -> inline(content)
    end)
  end
end
