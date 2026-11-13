defmodule Padocs.Document.SnippetTest do
  use ExUnit.Case, async: true

  alias Padocs.Document.Snippet

  test "is nil when nothing matched" do
    assert Snippet.segments("rien ici", %{fragment: "", highlighted: []}) == nil
  end

  test "marks the highlighted words" do
    text = "Le café et le chat"

    assert Snippet.segments(text, %{fragment: text, highlighted: [{15, 19}]}) ==
             [text: "Le café et le ", match: "chat"]
  end

  test "marks where the text is cut, and turns line breaks into spaces" do
    text = "Début.\nLe chat dort.\nPuis le chien arrive.\nFin."
    fragment = "Le chat dort.\nPuis le chien"

    assert Snippet.segments(text, %{fragment: fragment, highlighted: [{3, 7}, {22, 27}]}) ==
             [text: "…Le ", match: "chat", text: " dort. Puis le ", match: "chien", text: "…"]
  end
end
