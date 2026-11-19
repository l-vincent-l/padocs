defmodule Padocs.Document.ArchiveTest do
  use ExUnit.Case, async: true

  alias Padocs.Document.Archive

  # The documents of a plan as {title, parent title, path}, in their order.
  defp tree(%{documents: documents}) do
    titles = Map.new(documents, &{&1.key, &1.title})
    for d <- documents, do: {d.title, titles[d.parent], d.path}
  end

  describe "plan/2" do
    test "a folder becomes a parent document, a file a document, under a root named after the archive" do
      plan =
        Archive.plan(
          ["Notes.md", "Projets/Budget.md", "Projets/Planning.html", "Lettre.docx", "lisez.txt"],
          "Export.zip"
        )

      assert tree(plan) == [
               {"Export", nil, nil},
               {"Lettre", "Export", "Lettre.docx"},
               {"lisez", "Export", "lisez.txt"},
               {"Notes", "Export", "Notes.md"},
               {"Projets", "Export", nil},
               {"Budget", "Projets", "Projets/Budget.md"},
               {"Planning", "Projets", "Projets/Planning.html"}
             ]

      formats = Map.new(plan.documents, &{&1.path, &1.format})
      assert formats["Notes.md"] == "markdown"
      assert formats["lisez.txt"] == "markdown"
      assert formats["Projets/Planning.html"] == "html"
      assert formats["Lettre.docx"] == "docx"
      assert formats[nil] == nil
      assert plan.skipped == []
    end

    test "the single folder at the top of the archive is the root" do
      plan = Archive.plan(["Coffre/", "Coffre/A.md", "Coffre/Sous/B.md"], "coffre-2026.zip")

      assert tree(plan) == [
               {"Coffre", nil, nil},
               {"A", "Coffre", "Coffre/A.md"},
               {"Sous", "Coffre", nil},
               {"B", "Sous", "Coffre/Sous/B.md"}
             ]
    end

    test "a file and a folder of the same name make one document, as Notion exports" do
      plan =
        Archive.plan(
          [
            "Wiki/Accueil 0123456789abcdef0123456789abcdef.md",
            "Wiki/Accueil 0123456789abcdef0123456789abcdef/Équipe 89abcdef0123456789abcdef01234567.md"
          ],
          "notion.zip"
        )

      assert tree(plan) == [
               {"Wiki", nil, nil},
               {"Accueil", "Wiki", "Wiki/Accueil 0123456789abcdef0123456789abcdef.md"},
               {"Équipe", "Accueil",
                "Wiki/Accueil 0123456789abcdef0123456789abcdef/Équipe 89abcdef0123456789abcdef01234567.md"}
             ]
    end

    test "siblings are sorted by title, whatever the case" do
      plan = Archive.plan(["b.md", "A.md", "c/x.md"], "z.zip")
      assert Enum.map(plan.documents, & &1.title) == ["z", "A", "b", "c", "x"]
    end

    test "images are attachments, not documents" do
      plan = Archive.plan(["Notes.md", "img/Photo.PNG", "img/b.jpeg", "c.gif", "d.webp"], "a.zip")

      assert Enum.map(plan.documents, & &1.title) == ["a", "Notes"]
      assert Enum.sort(plan.attachments) == ["c.gif", "d.webp", "img/Photo.PNG", "img/b.jpeg"]
      assert plan.skipped == []
    end

    test "hidden and system files are left out silently" do
      plan =
        Archive.plan(
          [
            "Notes.md",
            ".obsidian/app.json",
            ".obsidian/notes.md",
            "Sous/.DS_Store",
            "__MACOSX/._Notes.md",
            "Thumbs.db",
            "desktop.ini"
          ],
          "a.zip"
        )

      assert Enum.map(plan.documents, & &1.title) == ["a", "Notes"]
      assert plan.skipped == []
      assert plan.attachments == []
    end

    test "unsupported files and unsafe paths are reported" do
      plan =
        Archive.plan(
          [
            "Notes.md",
            "budget.xlsx",
            "../evil.md",
            "/etc/passwd.md",
            "a/../../b.md",
            "x\\..\\y.md"
          ],
          "a.zip"
        )

      assert Enum.map(plan.documents, & &1.title) == ["a", "Notes"]

      assert Enum.sort(plan.skipped) == [
               %{path: "../evil.md", reason: :unsafe},
               %{path: "/etc/passwd.md", reason: :unsafe},
               %{path: "a/../../b.md", reason: :unsafe},
               %{path: "budget.xlsx", reason: :unsupported},
               %{path: "x\\..\\y.md", reason: :unsafe}
             ]
    end

    test "a folder without documents makes none" do
      plan = Archive.plan(["Notes.md", "vide/", "images/a.png", "autres/budget.xlsx"], "a.zip")

      assert Enum.map(plan.documents, & &1.title) == ["a", "Notes"]
      assert plan.skipped == [%{path: "autres/budget.xlsx", reason: :unsupported}]
    end

    test "Windows separators are read as folders" do
      plan = Archive.plan(["Dossier\\Notes.md", "Dossier\\Sous\\A.md"], "a.zip")

      # the path as in the archive, for the browser to find its entry
      assert tree(plan) == [
               {"Dossier", nil, nil},
               {"Notes", "Dossier", "Dossier\\Notes.md"},
               {"Sous", "Dossier", nil},
               {"A", "Sous", "Dossier\\Sous\\A.md"}
             ]
    end

    test "at most max_documents documents, the others reported" do
      paths = for i <- 1..5, do: "f#{i}.md"
      plan = Archive.plan(paths, "a.zip", max_documents: 3)

      # the root counts
      assert length(plan.documents) == 3
      assert Enum.map(plan.skipped, & &1.reason) == [:too_many, :too_many, :too_many]
    end

    test "parents come before their children, keys are unique" do
      plan = Archive.plan(["a/b/c/d.md", "a/e.md", "f.md"], "x.zip")
      keys = Enum.map(plan.documents, & &1.key)
      assert keys == Enum.uniq(keys)

      Enum.reduce(plan.documents, MapSet.new(), fn document, seen ->
        assert is_nil(document.parent) or MapSet.member?(seen, document.parent)
        MapSet.put(seen, document.key)
      end)
    end

    test "an archive without documents has no root" do
      plan = Archive.plan(["a.png", "b.xlsx"], "x.zip")
      assert plan.documents == []
    end
  end

  describe "front_matter/1" do
    test "reads the title and the tags, as an inline list" do
      assert Archive.front_matter("""
             title: "Ma note"
             tags: [recette, "dessert du soir", '#sucré']
             date: 2024-01-02
             """) == %{title: "Ma note", tags: ["recette", "dessert du soir", "sucré"]}
    end

    test "reads the tags as a dashed list, or separated by commas" do
      assert Archive.front_matter("tags:\n  - un\n  - \"deux mots\"\nother: x\n") ==
               %{title: nil, tags: ["un", "deux mots"]}

      assert Archive.front_matter("tags: un, #deux\ntitle: Titre") ==
               %{title: "Titre", tags: ["un", "deux"]}

      assert Archive.front_matter("tag: seul") == %{title: nil, tags: ["seul"]}
    end

    test "nothing usable" do
      assert Archive.front_matter("") == %{title: nil, tags: []}
      assert Archive.front_matter("title:\ntags: []") == %{title: nil, tags: []}
      assert Archive.front_matter(nil) == %{title: nil, tags: []}
    end
  end
end
