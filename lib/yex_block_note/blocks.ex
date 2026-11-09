defmodule YexBlockNote.Blocks do
  @moduledoc false

  # Reads the Yex.XmlFragment of a BlockNote document into the tree described
  # in `YexBlockNote`: the only module of YexBlockNote calling Yex.

  def read(%Yex.XmlFragment{} = fragment) do
    fragment
    |> Yex.XmlFragment.children()
    |> Enum.flat_map(&group/1)
  end

  # A blockGroup holds blockContainers.
  defp group(%Yex.XmlElement{} = group) do
    group
    |> Yex.XmlElement.children()
    |> Enum.flat_map(&container/1)
  end

  defp group(_text), do: []

  # A blockContainer holds its block, then the blockGroup of its nested blocks
  # if it has some.
  defp container(%Yex.XmlElement{} = container) do
    case container |> Yex.XmlElement.children() |> Enum.to_list() do
      [%Yex.XmlElement{} = block | nested] ->
        type = Yex.XmlElement.get_tag(block)

        [
          %{
            type: type,
            props: block |> Yex.XmlElement.get_attributes() |> props(),
            content: content(type, block),
            children: Enum.flat_map(nested, &group/1)
          }
        ]

      _ ->
        []
    end
  end

  defp container(_text), do: []

  defp props(attributes) do
    Map.new(attributes, fn
      {"level", level} -> {"level", level(level)}
      {"checked", checked} -> {"checked", to_string(checked) == "true"}
      attribute -> attribute
    end)
  end

  # BlockNote stores the level as a number, which y_ex reads as a float (or an
  # integer before y_ex 0.13); older documents may hold it as text.
  defp level(level) when is_integer(level), do: level
  defp level(level) when is_float(level), do: trunc(level)

  defp level(level) when is_binary(level) do
    case Integer.parse(level) do
      {level, _rest} -> level
      :error -> 1
    end
  end

  defp level(_level), do: 1

  # The rows of a table; each cell holds its text in tableParagraphs, joined
  # with a space.
  defp content("table", table) do
    rows =
      for row <- Yex.XmlElement.children(table) do
        for cell <- Yex.XmlElement.children(row) do
          cell
          |> Yex.XmlElement.children()
          |> Enum.map(&inline/1)
          |> Enum.intersperse([%{text: " ", styles: %{}}])
          |> Enum.concat()
        end
      end

    %{rows: rows}
  end

  defp content(_type, block), do: inline(block)

  # The inline content of an element: its texts, with their marks, and its
  # inline elements. Embeds (non-text inserts) are dropped.
  defp inline(%Yex.XmlElement{} = element) do
    element
    |> Yex.XmlElement.children()
    |> Enum.flat_map(fn
      %Yex.XmlText{} = text ->
        for %{insert: insert} = part when is_binary(insert) <- Yex.XmlText.to_delta(text),
            do: %{text: insert, styles: Map.get(part, :attributes, %{})}

      %Yex.XmlElement{} = element ->
        [
          %{
            type: Yex.XmlElement.get_tag(element),
            props: Yex.XmlElement.get_attributes(element),
            content: inline(element)
          }
        ]

      _other ->
        []
    end)
  end

  defp inline(_other), do: []
end
