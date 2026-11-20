// The import of an archive or a folder (js/archive_import.js), run in Node
// with a fake hook in place of the LiveView, a fake conversion in place of
// BlockNote's (the text it would convert, as the state) and a fake upload.
// Run with `npm test --prefix assets`.
import {test, describe} from "node:test"
import assert from "node:assert/strict"
import {zipSync, strToU8} from "fflate"
import {importArchive, importFolder, Links, splitFrontMatter} from "../js/archive_import.js"

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])

// The hook: replies with `plan` to the plan, an id to each document but
// those of `refused` keys; records what was pushed.
function fakeHook(plan, {refused = []} = {}) {
  const pushed = []
  return {
    pushed,
    documents: () => pushed.filter(([event]) => event === "import_archive_document").map(([, p]) => p),
    last: event => pushed.findLast(([e]) => e === event)?.[1],
    async push(event, payload) {
      pushed.push([event, payload])
      if (event === "import_archive_plan") return plan
      if (event === "import_archive_document") return refused.includes(payload.key) ? {} : {id: `id-${payload.key}`}
      return {}
    },
  }
}

// The conversion: the text as the state, to read it back.
const tools = (uploadFile = async () => ({id: "file-1", url: "/files/file-1"})) => ({
  toYjsState: async (content, format) => ({state: strToU8(`${format}:${content}`), fileIds: []}),
  uploadFile,
})

const text = payload => Buffer.from(payload.state, "base64").toString("utf8")

function zipFile(files, name = "Coffre.zip") {
  const entries = Object.fromEntries(Object.entries(files).map(([path, content]) => [path, typeof content === "string" ? strToU8(content) : content]))
  return new File([zipSync(entries)], name)
}

const plan = {
  documents: [
    {key: 0, parent: null, title: "Coffre", path: null, format: null, id: "id-0"},
    {key: 1, parent: 0, title: "Accueil", path: "Coffre/Accueil.md", format: "markdown", id: "id-1"},
    {key: 2, parent: 0, title: "Notes", path: null, format: null, id: "id-2"},
    {key: 3, parent: 2, title: "Recette", path: "Coffre/Notes/Recette.md", format: "markdown", id: "id-3"},
  ],
  attachments: ["Coffre/img/chat.png"],
  skipped: [{path: "Coffre/b.xlsx", reason: "unsupported"}],
}

describe("importArchive", () => {
  test("creates each document of the plan by its key, links and images rewritten", async () => {
    const hook = fakeHook(plan)
    const file = zipFile({
      "Coffre/Accueil.md": "---\ntags: [a]\n---\nVoir [[Recette]] et ![[chat.png]]",
      "Coffre/Notes/Recette.md": "Retour à l'[accueil](../Accueil.md)",
      "Coffre/img/chat.png": PNG,
      "Coffre/b.xlsx": "x",
    })

    await importArchive(hook, file, tools())

    assert.deepEqual(hook.last("import_archive_plan").paths.sort(), [
      "Coffre/Accueil.md",
      "Coffre/Notes/Recette.md",
      "Coffre/b.xlsx",
      "Coffre/img/chat.png",
    ])

    const [root, accueil, notes, recette] = hook.documents()
    assert.deepEqual(root, {key: 0, title: "Coffre"})
    assert.deepEqual(notes, {key: 2, title: "Notes"})
    assert.equal(accueil.front_matter, "tags: [a]")
    assert.deepEqual(accueil.file_ids, ["file-1"])
    assert.equal(text(accueil), "markdown:Voir [Recette](/documents/id-3) et \n\n![chat.png](/files/file-1)\n\n")
    assert.equal(text(recette), "markdown:Retour à l'[accueil](/documents/id-1)")

    assert.deepEqual(hook.last("import_archive_done"), {name: "Coffre.zip", root_id: "id-0", imported: 4, left_out: 1})
  })

  test("leaves out the documents under one not created, and counts their files", async () => {
    const hook = fakeHook(plan, {refused: [2]})
    await importArchive(hook, zipFile({"Coffre/Accueil.md": "a", "Coffre/Notes/Recette.md": "r"}), tools())

    assert.deepEqual(hook.documents().map(d => d.key), [0, 1, 2])
    assert.deepEqual(hook.last("import_archive_done"), {name: "Coffre.zip", root_id: "id-0", imported: 2, left_out: 2})
  })

  test("an image the server refuses is removed, its text kept", async () => {
    const hook = fakeHook(plan)
    const refuse = async () => {
      throw new Error("too_many_pending")
    }

    const file = zipFile({
      "Coffre/Accueil.md": "![un chat](img/chat.png)",
      "Coffre/Notes/Recette.md": "r",
      "Coffre/img/chat.png": PNG,
    })

    await importArchive(hook, file, tools(refuse))

    const accueil = hook.documents()[1]
    assert.equal(text(accueil), "markdown:un chat")
    assert.deepEqual(accueil.file_ids, [])
  })

  test("a file too large is left out", async () => {
    const hook = fakeHook(plan)
    await importArchive(hook, zipFile({"Coffre/Accueil.md": "x".repeat(2_000_001), "Coffre/Notes/Recette.md": "r"}), tools())

    assert.deepEqual(hook.documents().map(d => d.key), [0, 2, 3])
    assert.equal(hook.last("import_archive_done").left_out, 2)
  })

  test("a file that is not a zip is reported, and nothing planned", async () => {
    const hook = fakeHook(plan)
    await importArchive(hook, new File(["not a zip"], "faux.zip"), tools())

    assert.deepEqual(hook.pushed, [["import_failed", {name: "faux.zip", reason: "unreadable"}]])
  })
})

describe("importFolder", () => {
  // A file of a folder chosen with `webkitdirectory`.
  const inFolder = (path, content) => {
    const file = new File([content], path.split("/").pop())
    Object.defineProperty(file, "webkitRelativePath", {value: path})
    return file
  }

  test("imports the folder's files by their path, named after the folder", async () => {
    const hook = fakeHook(plan)
    const files = [inFolder("Coffre/Accueil.md", "Voir [[Recette]]"), inFolder("Coffre/Notes/Recette.md", "r"), inFolder("Coffre/img/chat.png", PNG)]

    await importFolder(hook, files, tools())

    assert.deepEqual(hook.last("import_archive_plan"), {
      name: "Coffre",
      paths: ["Coffre/Accueil.md", "Coffre/Notes/Recette.md", "Coffre/img/chat.png"],
    })
    assert.equal(text(hook.documents()[1]), "markdown:Voir [Recette](/documents/id-3)")
    assert.equal(hook.last("import_archive_done").imported, 4)
  })
})

describe("Links", () => {
  const links = new Links([
    {id: "R", path: null, title: "Coffre"},
    {id: "A", path: "Coffre/Notes/Recette crêpes.md", title: "Recette crêpes"},
    {id: "B", path: "Coffre/Autre page 0123456789abcdef0123456789abcdef.md", title: "Autre page"},
    {id: "C", path: "Coffre/pages/projets___padocs.md", title: "projets___padocs"},
    {id: "D", path: "Coffre/Site/index.html", title: "index"},
    {id: "P", path: "Coffre/photo.md", title: "photo"},
  ])
  const md = (input, from = "Coffre/x.md") => links.rewrite(input, from, "markdown")

  test("Obsidian's and Logseq's links, by name or title, whatever the case", () => {
    assert.equal(md("[[Recette crêpes]] [[recette crêpes|les crêpes]]"), "[Recette crêpes](/documents/A) [les crêpes](/documents/A)")
    assert.equal(md("[[Notes/Recette crêpes#Pâte]]"), "[Notes/Recette crêpes](/documents/A)")
    assert.equal(md("[[Autre page]]"), "[Autre page](/documents/B)")
    assert.equal(md("[[projets/padocs]]"), "[projets/padocs](/documents/C)")
  })

  test("Markdown links, by their path relative to the file", () => {
    assert.equal(md("[ici](Autre%20page%200123456789abcdef0123456789abcdef.md)"), "[ici](/documents/B)")
    assert.equal(md('[ici](<../Autre page 0123456789abcdef0123456789abcdef.md> "titre")', "Coffre/Notes/y.md"), "[ici](/documents/B)")
    assert.equal(md("[y](photo)"), "[y](/documents/P)")
  })

  test("HTML links", () => {
    assert.equal(
      links.rewrite('<a href="Site/index.html#top">x</a> <a href="https://e.org">y</a>', "Coffre/z.html", "html"),
      '<a href="/documents/D">x</a> <a href="https://e.org">y</a>',
    )
  })

  test("other links stay as written", () => {
    const kept = "[[Inconnue]] [web](https://x.org/a.md) [ancre](#h) ![[Recette crêpes]] [x](photo.png) [[a [b]|x]]"
    assert.equal(md(kept), kept)
  })

  test("a label's brackets are escaped", () => {
    assert.equal(md("[[Recette crêpes|a [b] c]]"), "[[Recette crêpes|a [b] c]]")
    assert.equal(md("[[Recette crêpes|a \\ c]]"), "[a \\\\ c](/documents/A)")
  })
})

describe("splitFrontMatter", () => {
  test("YAML between --- lines", () => {
    assert.deepEqual(splitFrontMatter("﻿---\ntitle: T\n---\nCorps"), {frontMatter: "title: T", body: "Corps"})
  })

  test("Logseq's properties, maybe in the first block", () => {
    assert.deepEqual(splitFrontMatter("title:: T\ntags:: [[a]]\n\n- bloc"), {frontMatter: "title:: T\ntags:: [[a]]\n", body: "\n- bloc"})
    assert.deepEqual(splitFrontMatter("- title:: T\n  tags:: a\n- bloc"), {frontMatter: "- title:: T\n  tags:: a\n", body: "- bloc"})
  })

  test("none", () => {
    assert.deepEqual(splitFrontMatter("Un texte: avec deux points"), {frontMatter: null, body: "Un texte: avec deux points"})
  })
})
