defmodule YexBlockNote.TextTest do
  use ExUnit.Case, async: true

  import YexBlockNote.Fixtures

  describe "to_text/1" do
    test "has one line per block holding text, nested ones included" do
      fragment =
        fragment_with([
          {"heading", "Title", [], %{"level" => "1"}},
          {"paragraph", ""},
          {"bulletListItem", "Item", [{"bulletListItem", "Sub item"}]}
        ])

      assert YexBlockNote.to_text(fragment) == "Title\nItem\nSub item"
    end
  end

  describe "empty?/1" do
    test "is true without text and with only paragraphs" do
      assert YexBlockNote.empty?([])
      assert YexBlockNote.empty?(fragment_with([{"paragraph", ""}, {"paragraph", " "}]))
    end

    test "is false with text or another block" do
      refute YexBlockNote.empty?(fragment_with([{"paragraph", "hello"}]))
      refute YexBlockNote.empty?(fragment_with([{"image", ""}]))
      refute YexBlockNote.empty?(fragment_with([{"paragraph", "", [{"paragraph", "nested"}]}]))
    end

    test "is false with an inline element, even without text" do
      mention = %{type: "mention", props: %{"user" => "1"}, content: []}

      refute YexBlockNote.empty?([
               %{type: "paragraph", props: %{}, content: [mention], children: []}
             ])
    end
  end
end
