defmodule YBlocknote.TypstTest do
  use ExUnit.Case, async: true

  alias YBlocknote.Typst, as: T

  # Document as written by the BlockNote editor: one block per
  # `{tag, text, nested blocks, attributes}`, the last two being optional; a
  # text is a string, or a delta (a list of `%{insert, attributes}`).
  defp fragment_with(blocks) do
    fragment = new_fragment()
    Yex.XmlFragment.push(fragment, Yex.XmlElementPrelim.empty("blockGroup"))
    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    push_blocks(group, blocks)

    fragment
  end

  defp new_fragment, do: Yex.Doc.get_xml_fragment(Yex.Doc.new(), "blocknote")

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

      content =
        case text do
          "" -> []
          [_ | _] = delta -> [Yex.XmlTextPrelim.from(delta)]
          text -> [Yex.XmlTextPrelim.from(text)]
        end

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

  # The markup after the page and text settings.
  defp body(fragment, opts \\ []) do
    [_preamble, body] = fragment |> T.to_typst(opts) |> String.split("\n\n", parts: 2)
    String.trim_trailing(body, "\n")
  end

  # The markup compiles, into a PDF.
  defp assert_compiles(fragment, opts \\ []) do
    assert {:ok, "%PDF" <> _} = fragment |> T.to_typst(opts) |> Typst.render_to_pdf()
  end

  test "string/1 escapes what a Typst string literal needs" do
    assert T.string(~S|a "b" \ c|) == ~S|"a \"b\" \\ c"|
    assert T.string("one\ntwo\tthree") == ~S|"one\ntwo\tthree"|
  end

  test "the text is never markup nor code, whatever its characters" do
    text = ~S|= #import "x": * _a_ *b* $x$ // c /* d @e <f> [g] ~ - + 1. \ `h`|
    fragment = fragment_with([{"paragraph", text}])

    assert body(fragment) == "#" <> T.string(text)
    assert_compiles(fragment)
  end

  test "settings, and the title when given" do
    fragment = fragment_with([{"paragraph", "Text"}])
    typst = T.to_typst(fragment, title: ~S|Le "titre" #1|, lang: "fr")

    assert typst =~ ~S|#set document(title: "Le \"titre\" #1")|
    assert typst =~ ~S|#set text(lang: "fr", size: 11pt)|
    assert typst =~ ~S|text(size: 1.8em, weight: "bold", "Le \"titre\" #1")|
    assert T.to_typst(new_fragment()) =~ "#set document(title: none)"

    assert_compiles(fragment, title: "Titre")
    assert_compiles(new_fragment())
  end

  test "headings, paragraphs and nested lists" do
    fragment =
      fragment_with([
        {"heading", "Title", [], %{"level" => 2.0}},
        {"paragraph", ""},
        {"paragraph", "Text"},
        {"bulletListItem", "Item",
         [{"numberedListItem", "Sub one"}, {"numberedListItem", "Sub two"}]},
        {"checkListItem", "Done", [], %{"checked" => true}},
        {"checkListItem", "Todo"},
        {"paragraph", "Parent", [{"paragraph", "Child"}]}
      ])

    assert body(fragment) ==
             """
             #heading(level: 2)[#"Title"]

             #"Text"

             - #"Item"
               + #"Sub one"
               + #"Sub two"
             - #"☑ "#"Done"
             - #"☐ "#"Todo"

             #"Parent"

             #pad(left: 1.5em)[
               #"Child"
             ]\
             """

    assert_compiles(fragment)
  end

  test "the formatting of the text, colors and line breaks included" do
    fragment =
      fragment_with([
        {"paragraph",
         [
           %{insert: "Plain "},
           %{insert: "bold", attributes: %{"bold" => %{}}},
           %{insert: " "},
           %{insert: "both", attributes: %{"bold" => %{}, "italic" => %{}}},
           %{insert: " "},
           %{insert: "red", attributes: %{"textColor" => %{"stringValue" => "red"}}},
           %{insert: " "},
           %{insert: "marked", attributes: %{"backgroundColor" => "yellow"}},
           %{insert: " "},
           %{insert: "x = 1", attributes: %{"code" => %{}}},
           %{insert: " "},
           %{insert: "a link", attributes: %{"link" => %{"href" => ~S|https://e.x/?q="1"|}}},
           %{insert: "\nsecond line"}
         ]}
      ])

    assert body(fragment) ==
             ~S|#"Plain "#strong[#"bold"]#" "#emph[#strong[#"both"]]#" "| <>
               ~S|#text(fill: rgb("#e03e3e"))[#"red"]#" "| <>
               ~S|#highlight(fill: rgb("#fbf3db"))[#"marked"]#" "#raw("x = 1")#" "| <>
               ~S|#link("https://e.x/?q=\"1\"")[#"a link"]#linebreak()#"second line"|

    assert_compiles(fragment)
  end

  test "quotes, code, tables, dividers and files" do
    table =
      Yex.XmlElementPrelim.new("table", [
        Yex.XmlElementPrelim.new("tableRow", [
          cell("Name"),
          cell("Count")
        ]),
        Yex.XmlElementPrelim.new("tableRow", [
          cell("Apples"),
          cell("3")
        ])
      ])

    fragment =
      fragment_with([
        {"quote", "Wise words"},
        {"codeBlock", "IO.puts(\"#hi\")", [], %{"language" => "elixir"}}
      ])

    {:ok, group} = Yex.XmlFragment.fetch(fragment, 0)
    Yex.XmlElement.push(group, Yex.XmlElementPrelim.new("blockContainer", [table]))

    push_blocks(group, [
      {"divider", ""},
      {"image", "", [], %{"url" => "https://e.x/a.png", "caption" => "A cat"}},
      {"file", "", [], %{"url" => "https://e.x/b.pdf", "name" => "#b.pdf"}},
      {"image", "", [], %{}}
    ])

    assert body(fragment) ==
             """
             #quote(block: true)[#"Wise words"]

             #raw(block: true, lang: "elixir", "IO.puts(\\"#hi\\")")

             #table(
               columns: 2,
               table.header([#"Name"], [#"Count"]),
               [#"Apples"],
               [#"3"]
             )

             #line(length: 100%, stroke: 0.5pt + gray)

             #link("https://e.x/a.png")[#"Image : A cat"]

             #link("https://e.x/b.pdf")[#"Fichier : #b.pdf"]\
             """

    assert_compiles(fragment)
  end

  test "the alignment of paragraphs" do
    fragment =
      fragment_with([
        {"paragraph", "Centered", [], %{"textAlignment" => "center"}},
        {"paragraph", "Justified", [], %{"textAlignment" => "justify"}}
      ])

    assert body(fragment) == ~s|#align(center)[#"Centered"]\n\n#par(justify: true)[#"Justified"]|
    assert_compiles(fragment)
  end

  defp cell(text) do
    Yex.XmlElementPrelim.new("tableCell", [
      Yex.XmlElementPrelim.new("tableParagraph", [Yex.XmlTextPrelim.from(text)])
    ])
  end
end
