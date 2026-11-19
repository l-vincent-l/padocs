// The import of a zip, for the DocumentImport hook (document_import.js): the
// archive is read in the browser, the server plans its tree of documents from
// the paths of its entries (see Padocs.Document.Archive), then each document
// is converted by BlockNote, parents first, and sent to the server, which
// creates it under its parent. The images a Markdown or HTML file links to,
// found in the archive, are uploaded and linked by their URL. At the end, the
// server tells what was imported and opens the root.
import {toBase64} from "./base64"
import {MAX_BYTES, MAX_DOCX_BYTES} from "./document_import"
import {uploadFile} from "./blocknote/upload"

const MAX_ARCHIVE_BYTES = 200_000_000

export async function importArchive(hook, file, toYjsState) {
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

  const plan = await hook.push("import_archive_plan", {name: file.name, paths: Object.keys(entries)})
  const images = new Images(entries, plan.attachments || [])
  // the id of each document created, by its key in the plan
  const ids = new Map()
  let imported = 0
  let leftOut = (plan.skipped || []).length
  if (leftOut > 0) console.info("left out of the import:", plan.skipped)

  for (const node of plan.documents || []) {
    const parentId = node.parent === null ? null : ids.get(node.parent)

    // under a document not created: left out with it
    if (node.parent !== null && !parentId) {
      if (node.path) leftOut++
      continue
    }

    let content = {}
    if (node.path) {
      try {
        content = await convert(node, entries[node.path], images, toYjsState)
      } catch (error) {
        console.error(`${node.path} left out of the import`, error)
        leftOut++
        continue
      }
    }

    const reply = await hook.push("import_archive_document", {title: node.title, parent_id: parentId, ...content})

    if (reply.id) {
      ids.set(node.key, reply.id)
      imported++
    } else if (node.path) {
      leftOut++
    }
  }

  const root = plan.documents?.[0]
  return hook.push("import_archive_done", {
    name: file.name,
    root_id: root ? ids.get(root.key) : null,
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
async function convert(node, bytes, images, toYjsState) {
  const maxBytes = node.format === "docx" ? MAX_DOCX_BYTES : MAX_BYTES
  if (bytes.length > maxBytes) throw new Error(`too large (${bytes.length} bytes)`)

  if (node.format === "docx") {
    const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength)
    const {state, fileIds} = await toYjsState(buffer, "docx")
    return {state: toBase64(state), file_ids: fileIds}
  }

  const text = new TextDecoder().decode(bytes)
  const {frontMatter, body} = node.format === "markdown" ? splitFrontMatter(text) : {frontMatter: null, body: text}
  const linked = await images.link(body, node.path, node.format)
  const {state} = await toYjsState(linked.text, node.format)

  return {state: toBase64(state), front_matter: frontMatter, file_ids: linked.fileIds}
}

// The YAML between the `---` lines opening a file, read by the server, and
// the rest.
function splitFrontMatter(text) {
  const match = text.replace(/^﻿/, "").match(/^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/)
  if (!match) return {frontMatter: null, body: text}
  return {frontMatter: match[1], body: text.replace(/^﻿/, "").slice(match[0].length)}
}

// The images of the archive, found by the path a document gives (relative to
// it), else by their name, as Obsidian links them.
class Images {
  constructor(entries, paths) {
    this.entries = entries
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
          const file = await uploadFile("/files", this.entries[path])
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
