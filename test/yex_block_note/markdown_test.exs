defmodule YexBlockNote.MarkdownTest do
  use ExUnit.Case, async: true

  import YexBlockNote.Fixtures

  describe "to_markdown/1" do
    test "is empty for an empty body" do
      assert YexBlockNote.to_markdown(new_fragment()) == ""
      assert YexBlockNote.to_markdown(fragment_with([{"paragraph", ""}])) == ""
    end

    # BlockNote stores the level as a number, which y_ex reads as a float.
    test "reads the heading level as a number or as text" do
      fragment =
        fragment_with([
          {"heading", "One", [], %{"level" => 1}},
          {"heading", "Two", [], %{"level" => 2.0}},
          {"heading", "Three", [], %{"level" => "3"}}
        ])

      assert YexBlockNote.to_markdown(fragment) == "# One\n\n## Two\n\n### Three"
    end

    test "separates blocks with a blank line and skips empty paragraphs" do
      fragment =
        fragment_with([
          {"heading", "Title", [], %{"level" => "2"}},
          {"paragraph", "First"},
          {"paragraph", ""},
          {"quote", "Quoted"},
          {"codeBlock", "x = 1", [], %{"language" => "elixir"}}
        ])

      assert YexBlockNote.to_markdown(fragment) ==
               "## Title\n\nFirst\n\n> Quoted\n\n```elixir\nx = 1\n```"
    end

    test "keeps list items together and nests children under their item" do
      fragment =
        fragment_with([
          {"numberedListItem", "One", [{"bulletListItem", "Sub"}]},
          {"numberedListItem", "Two"},
          {"checkListItem", "Done", [], %{"checked" => "true"}},
          {"checkListItem", "Todo", [], %{"checked" => "false"}},
          {"paragraph", "After"},
          {"numberedListItem", "Again"}
        ])

      assert YexBlockNote.to_markdown(fragment) ==
               "1. One\n   - Sub\n2. Two\n- [x] Done\n- [ ] Todo\n\nAfter\n\n1. Again"
    end

    test "writes the formatting of the text" do
      fragment = new_fragment()

      text =
        Yex.XmlTextPrelim.from([
          %{insert: "Plain "},
          %{insert: "bold ", attributes: %{"bold" => %{}}},
          %{insert: "both", attributes: %{"bold" => %{}, "italic" => %{}}},
          %{insert: " and "},
          %{insert: "a link", attributes: %{"link" => %{"href" => "https://example.com"}}}
        ])

      Yex.XmlFragment.push(
        fragment,
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("paragraph", [text])
          ])
        ])
      )

      assert YexBlockNote.to_markdown(fragment) ==
               "Plain **bold** _**both**_ and [a link](https://example.com)"
    end

    test "writes images with their caption" do
      fragment =
        fragment_with([
          {"image", "", [], %{"url" => "https://example.com/a.png", "caption" => "A cat"}}
        ])

      assert YexBlockNote.to_markdown(fragment) == "![A cat](https://example.com/a.png)"
    end
  end
end
