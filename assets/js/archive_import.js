// The import of a zip, or of a folder, for the DocumentImport hook
// (document_import.js): the archive is read in the browser, the server plans
// its tree of documents from the paths of its entries (see
// Padocs.Document.Archive), then each document is converted by BlockNote,
// parents first, and sent to the server, which creates it under its parent.
// The images a Markdown or HTML file links to, found in the archive, are
// uploaded and linked by their URL. Its links to other files of the archive
// become links to their documents, whose ids the plan gives before any is
// created. At the end, the server tells what was imported and opens the root.
//
// `hook` is the DocumentImport hook (its `push`), `toYjsState` BlockNote's
// conversion (blocknote/convert.ts) and `uploadFile` the upload of an image
// (blocknote/upload.ts), given by the hook: the tests (assets/test) run
// this module in Node with their own.
import {toBase64} from "./base64.js"
import {MAX_ARCHIVE_BYTES, MAX_BYTES, MAX_DOCX_BYTES} from "./import_limits.js"

export async function importArchive(hook, file, {toYjsState, uploadFile}) {
  if (file.size > MAX_ARCHIVE_BYTES) {
    return hook.push("import_failed", {name: file.name, reason: "too_large", max_bytes: MAX_ARCHIVE_BYTES})
  }

  let entries
  try {
    entries = await readZip(file)
  } catch (error) {
    console.error(error)
    return hook.push("import_failed", {name: file.name, reason: "unreadable"})
  }

  return importEntries(hook, file.name, entries, {toYjsState, uploadFile})
}

// A folder chosen by an input with `webkitdirectory`: its files, by their
// path from the folder (`Vault/notes/a.md`), read when used only, a folder
// often holding much more than its documents.
export async function importFolder(hook, files, {toYjsState, uploadFile}) {
  const entries = {}
  for (const file of files) entries[file.webkitRelativePath || file.name] = file
  const name = (files[0]?.webkitRelativePath || "").split("/")[0] || "Import"
  return importEntries(hook, name, entries, {toYjsState, uploadFile})
}

// `entries`, the files by path, each its bytes or a File.
async function importEntries(hook, name, entries, {toYjsState, uploadFile}) {
  const plan = await hook.push("import_archive_plan", {name, paths: Object.keys(entries)})
  const images = new Images(entries, plan.attachments || [], uploadFile)
  const links = new Links(plan.documents || [])
  // the keys of the documents created
  const created = new Set()
  let imported = 0
  let leftOut = (plan.skipped || []).length
  if (leftOut > 0) console.info("left out of the import:", plan.skipped)

  for (const node of plan.documents || []) {
    // under a document not created: left out with it
    if (node.parent !== null && !created.has(node.parent)) {
      if (node.path) leftOut++
      continue
    }

    let content = {}
    if (node.path) {
      try {
        content = await convert(node, entries[node.path], images, links, toYjsState)
      } catch (error) {
        console.error(`${node.path} left out of the import`, error)
        leftOut++
        continue
      }
    }

    const reply = await hook.push("import_archive_document", {key: node.key, title: node.title, ...content})

    if (reply.id) {
      created.add(node.key)
      imported++
    } else if (node.path) {
      leftOut++
    }
  }

  const root = plan.documents?.[0]
  return hook.push("import_archive_done", {
    name,
    root_id: root && created.has(root.key) ? root.id : null,
    imported,
    left_out: leftOut,
  })
}

// The files of the zip, by path; folders left out.
async function readZip(file) {
  const {unzip} = await import("fflate")
  const bytes = new Uint8Array(await file.arrayBuffer())

  return new Promise((resolve, reject) => {
    unzip(bytes, {filter: entry => !entry.name.endsWith("/")}, (error, entries) =>
      error ? reject(error) : resolve(entries),
    )
  })
}

// The state of the document of `node`, its front matter and the files of its
// images.
async function convert(node, entry, images, links, toYjsState) {
  const maxBytes = node.format === "docx" ? MAX_DOCX_BYTES : MAX_BYTES
  const size = entry.size ?? entry.length
  if (size > maxBytes) throw new Error(`too large (${size} bytes)`)
  const bytes = await bytesOf(entry)

  if (node.format === "docx") {
    const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    const {state, fileIds} = await toYjsState(buffer, "docx")
    return {state: toBase64(state), file_ids: fileIds}
  }

  const text = new TextDecoder().decode(bytes)
  const {frontMatter, body} = node.format === "markdown" ? splitFrontMatter(text) : {frontMatter: null, body: text}
  const linked = await images.link(body, node.path, node.format)
  const {state} = await toYjsState(links.rewrite(linked.text, node.path, node.format), node.format)

  return {state: toBase64(state), front_matter: frontMatter, file_ids: linked.fileIds}
}

// The bytes of an entry, read from its File for a folder.
async function bytesOf(entry) {
  return entry instanceof Blob ? new Uint8Array(await entry.arrayBuffer()) : entry
}

// The YAML between the `---` lines opening a file, or the properties opening
// a Logseq page (`title:: …` lines, maybe in its first block, `- title:: …`),
// read by the server, and the rest.
export function splitFrontMatter(text) {
  text = text.replace(/^﻿/, "")
  const yaml = text.match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/)
  if (yaml) return {frontMatter: yaml[1], body: text.slice(yaml[0].length)}

  const properties = text.match(/^(?:[ \t]*(?:-[ \t]+)?[\w-]+::(?:[ \t].*)?(?:\r?\n|$))+/)
  if (properties) return {frontMatter: properties[0], body: text.slice(properties[0].length)}

  return {frontMatter: null, body: text}
}

// The images of the archive, found by the path a document gives (relative to
// it), else by their name, as Obsidian links them.
class Images {
  constructor(entries, paths, uploadFile) {
    this.entries = entries
    this.uploadFile = uploadFile
    this.byPath = new Map()
    this.byName = new Map()

    for (const path of paths) {
      const normalized = path.replaceAll("\\", "/")
      this.byPath.set(normalized, path)
      const name = normalized.split("/").pop().toLowerCase()
      if (!this.byName.has(name)) this.byName.set(name, path)
    }
  }

  // `text` with the images of the archive it links to uploaded (once each)
  // and linked by their URL; those the server refuses, removed. Other links
  // (external, or to files not in the archive) stay as written.
  async link(text, documentPath, format) {
    const pattern =
      format === "html"
        ? /<img\b[^>]*?\bsrc\s*=\s*(["'])(.*?)\1[^>]*>/gi
        : /!\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]|!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+["'][^"']*["'])?\s*\)/g

    const matches = [...text.matchAll(pattern)]
    // the URL of each target, of each path found (null: refused)
    const urls = new Map()
    const uploaded = new Map()
    const fileIds = []

    for (const match of matches) {
      const target = format === "html" ? match[2] : match[1] || match[3]
      if (urls.has(target)) continue
      const path = this.find(target, documentPath)
      if (!path) continue

      if (!uploaded.has(path)) {
        try {
          const file = await this.uploadFile("/files", this.entries[path])
          fileIds.push(file.id)
          uploaded.set(path, file.url)
        } catch (error) {
          console.warn(`image ${path} left out of the import`, error)
          uploaded.set(path, null)
        }
      }

      urls.set(target, uploaded.get(path))
    }

    const linked = text.replace(pattern, (whole, ...groups) => {
      if (format === "html") {
        const url = urls.get(groups[1])
        if (url === undefined) return whole
        return url ? whole.replace(groups[1], url) : ""
      }

      const [wiki, alt, target] = groups
      const url = urls.get(wiki || target)
      if (url === undefined) return whole
      if (url === null) return alt || ""
      // on its own line: BlockNote's images are blocks, one inside a
      // paragraph would be dropped
      return `\n\n![${alt || wiki || ""}](${url})\n\n`
    })

    return {text: linked, fileIds}
  }

  find(target, documentPath) {
    if (isExternal(target)) return null
    let decoded = target
    try {
      decoded = decodeURIComponent(target)
    } catch (_error) {
      // left as written
    }

    const folder = documentPath.replaceAll("\\", "/").split("/").slice(0, -1)
    const resolved = resolve(decoded.startsWith("/") ? [] : folder, decoded)
    return this.byPath.get(resolved) || this.byName.get(decoded.split("/").pop().toLowerCase()) || null
  }
}

// The documents of the plan, found by the path a link gives (relative to its
// file, with or without its extension), else by their file's name or their
// title, as Obsidian and Logseq link pages by name (`[[Page]]`).
export class Links {
  constructor(documents) {
    this.byPath = new Map()
    this.byName = new Map()

    for (const {id, path, title} of documents) {
      if (path) {
        const normalized = path.replaceAll("\\", "/")
        this.byPath.set(normalized, id)
        this.byPath.set(withoutExtension(normalized), id)
        this.addName(withoutExtension(normalized.split("/").pop()), id)
      }
      this.addName(title, id)
    }
  }

  addName(name, id) {
    const key = name.toLowerCase()
    if (!this.byName.has(key)) this.byName.set(key, id)
  }

  // `text` with its links to files of the archive (`[[Page]]`,
  // `[[Page|text]]`, `[text](Other%20page.md)`, `<a href>`) linking to their
  // documents. Other links stay as written.
  rewrite(text, documentPath, format) {
    if (format === "html") {
      return text.replace(/(<a\b[^>]*?\bhref\s*=\s*)(["'])(.*?)\2/gi, (whole, start, quote, target) => {
        const id = this.find(target, documentPath)
        return id ? `${start}${quote}/documents/${id}${quote}` : whole
      })
    }

    return text
      .replace(/(?<!!)\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|([^\]]*))?\]\]/g, (whole, target, label) => {
        const id = this.findByName(target.trim(), documentPath)
        return id ? `[${escapeLabel(label?.trim() || target.trim())}](/documents/${id})` : whole
      })
      .replace(
        /(?<!!)\[([^\]]*)\]\(\s*(?:<([^>]+)>|([^)\s]+))(\s+["'][^"']*["'])?\s*\)/g,
        (whole, label, angled, plain) => {
          const id = this.find(angled || plain, documentPath)
          return id ? `[${label}](/documents/${id})` : whole
        },
      )
  }

  // A link's target, a path relative to the file of `documentPath`.
  find(target, documentPath) {
    if (isExternal(target) || target.startsWith("#")) return null
    const path = decode(target.replace(/[?#].*$/, ""))
    if (path === "") return null

    const folder = documentPath.replaceAll("\\", "/").split("/").slice(0, -1)
    const resolved = resolve(path.startsWith("/") ? [] : folder, path)
    const name = path.split("/").pop()
    // by name only for a document's file, or a name without extension: a
    // link to `photo.png` is not one to the page "photo"
    const byName = withoutExtension(name) !== name || !/\.\w+$/.test(name)
    return this.byPath.get(resolved) || (byName && this.byName.get(withoutExtension(name).toLowerCase())) || null
  }

  // A page's name, as `[[Page]]` or `[[folder/Page]]` give it; Logseq writes
  // the `/` of a namespace (`[[a/b]]`) as `___` in the file's name.
  findByName(name, documentPath) {
    return (
      this.find(name, documentPath) ||
      this.byName.get(name.toLowerCase()) ||
      this.byName.get(name.replaceAll("/", "___").toLowerCase()) ||
      null
    )
  }
}

function withoutExtension(name) {
  return name.replace(/\.(md|markdown|txt|html?|docx)$/i, "")
}

function decode(text) {
  try {
    return decodeURIComponent(text)
  } catch (_error) {
    return text
  }
}

// The text of a Markdown link, its brackets escaped.
function escapeLabel(label) {
  return label.replace(/[[\]\\]/g, "\\$&")
}

function isExternal(target) {
  return /^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith("//")
}

// `path` relative to the `folder` segments, without its "." and "..".
function resolve(folder, path) {
  const segments = [...folder]
  for (const segment of path.split("/")) {
    if (segment === "" || segment === ".") continue
    if (segment === "..") segments.pop()
    else segments.push(segment)
  }
  return segments.join("/")
}
