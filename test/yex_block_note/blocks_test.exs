defmodule YexBlockNote.BlocksTest do
  use ExUnit.Case, async: true

  import YexBlockNote.Fixtures

  describe "to_blocks/1" do
    test "is empty for an empty fragment" do
      assert YexBlockNote.to_blocks(new_fragment()) == []
    end

    test "reads blocks, their props, inline content and nested blocks" do
      blocks =
        fragment_with([
          {"heading", [%{insert: "Bold", attributes: %{"bold" => %{}}}, %{insert: " title"}], [],
           %{"level" => 2.0}},
          {"checkListItem", "Done", [{"paragraph", "Nested"}], %{"checked" => "true"}}
        ])
        |> YexBlockNote.to_blocks()

      assert [
               %{
                 type: "heading",
                 props: %{"level" => 2},
                 content: [
                   %{text: "Bold", styles: %{"bold" => %{}}},
                   %{text: " title", styles: %{}}
                 ],
                 children: []
               },
               %{
                 type: "checkListItem",
                 props: %{"checked" => true},
                 content: [%{text: "Done", styles: %{}}],
                 children: [%{type: "paragraph", content: [%{text: "Nested"}], children: []}]
               }
             ] = blocks
    end

    # BlockNote stores the level as a number, which y_ex reads as a float.
    test "reads the heading level as a number or as text" do
      levels =
        for %{props: %{"level" => level}} <-
              fragment_with([
                {"heading", "One", [], %{"level" => 1}},
                {"heading", "Two", [], %{"level" => 2.0}},
                {"heading", "Three", [], %{"level" => "3"}}
              ])
              |> YexBlockNote.to_blocks(),
            do: level

      assert levels == [1, 2, 3]
    end

    test "reads tables as rows of cells" do
      fragment = new_fragment()

      cell = fn text ->
        Yex.XmlElementPrelim.new("tableCell", [
          Yex.XmlElementPrelim.new("tableParagraph", [Yex.XmlTextPrelim.from(text)])
        ])
      end

      Yex.XmlFragment.push(
        fragment,
        Yex.XmlElementPrelim.new("blockGroup", [
          Yex.XmlElementPrelim.new("blockContainer", [
            Yex.XmlElementPrelim.new("table", [
              Yex.XmlElementPrelim.new("tableRow", [cell.("A"), cell.("B")])
            ])
          ])
        ])
      )

      assert [%{type: "table", content: %{rows: [[[%{text: "A"}], [%{text: "B"}]]]}}] =
               YexBlockNote.to_blocks(fragment)
    end
  end
end
