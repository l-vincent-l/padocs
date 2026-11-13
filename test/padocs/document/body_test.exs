defmodule Padocs.Document.BodyTest do
  use ExUnit.Case, async: true

  alias Padocs.Document.Body

  # Body as written by the BlockNote editor: one block per
  # `{tag, text, nested blocks, attributes}`, the last two being optional.
  defp doc_with(blocks) do
    doc = Yex.Doc.new()
    fragment = Yex.Doc.get_xml_fragment(doc, "document-store")
    Yex.XmlFragment.push(fragment, Yex.XmlElementPrelim.empty("blockGroup"))
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    push_blocks(group, blocks)

    doc
  end

  # Attributes are set once the elements exist: Yex ignores those of prelims.
  defp push_blocks(group, blocks) do
    for block <- blocks do
      {tag, text, children, attributes} =
        case block do
          {tag, text} -> {tag, text, [], %{}}
          {tag, text, children} -> {tag, text, children, %{}}
          block -> block
        end

      Yex.XmlElement.push(group, Yex.XmlElementPrelim.empty("blockContainer"))
      {:ok, container} = Yex.XmlElement.fetch(group, Yex.XmlElement.length(group) - 1)

      content = if text == "", do: [], else: [Yex.XmlTextPrelim.from(text)]
      Yex.XmlElement.push(container, Yex.XmlElementPrelim.new(tag, content))
      {:ok, element} = Yex.XmlElement.fetch(container, 0)
      for {key, value} <- attributes, do: Yex.XmlElement.insert_attribute(element, key, value)

      if children != [] do
        Yex.XmlElement.push(container, Yex.XmlElementPrelim.empty("blockGroup"))
        {:ok, nested} = Yex.XmlElement.fetch(container, 1)
        push_blocks(nested, children)
      end
    end
  end

  describe "excerpt/1" do
    test "is nil for an empty body" do
      assert Body.excerpt(Yex.Doc.new()) == nil
      assert Body.excerpt(doc_with([{"paragraph", ""}])) == nil
    end

    test "has the first three non-blank blocks, one per line, nested ones included" do
      doc =
        doc_with([
          {"heading", "Title"},
          {"paragraph", "  "},
          {"bulletListItem", "Item", [{"bulletListItem", "Sub item"}]},
          {"paragraph", "Not shown"}
        ])

      assert Body.excerpt(doc) == "Title\nItem\nSub item"
    end

    test "keeps the text of formatted parts" do
      doc = Yex.Doc.new()

      text =
        Yex.XmlTextPrelim.from([
          %{insert: "Hello "},
          %{insert: "world", attributes: %{"bold" => true}}
        ])

      doc
      |> Yex.Doc.get_xml_fragment("document-store")
      |> Yex.XmlFragment.push(
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [text])
          ])
        ])
      )

      assert Body.excerpt(doc) == "Hello world"
    end

    test "is cut to 280 characters" do
      excerpt = Body.excerpt(doc_with([{"paragraph", String.duplicate("a", 400)}]))

      assert String.length(excerpt) == 280
    end
  end
end
