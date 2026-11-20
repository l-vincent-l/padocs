// Hook of the file input of a document's menu: each chosen file (Markdown, HTML,
// plain text or Word) is converted to a document by BlockNote, in the browser, and its
// Yjs state sent to the server, which creates the document. One imported file
// is opened. A zip is imported as a tree of documents (see archive_import.js),
// and so is a folder, chosen by an input with `webkitdirectory`.
// The BlockNote bundle is only loaded on the first import.
import {toBase64} from "./base64"
import {importArchive, importFolder} from "./archive_import"
import {uploadFile} from "./blocknote/upload"
import {MAX_BYTES, MAX_DOCX_BYTES} from "./import_limits"

export const DocumentImport = {
  mounted() {
    this.el.addEventListener("change", () => this.importFiles([...this.el.files]))
  },

  async importFiles(files) {
    // so that choosing the same file again triggers a change
    this.el.value = ""
    if (files.length === 0) return

    // the menu it was chosen from closes, the whole stays busy until done
    const menu = this.el.closest("[data-import-menu]")
    if (menu) this.js().hide(menu)
    const card = this.el.closest("[data-import]")
    this.js().setAttribute(card, "aria-busy", "true")
    const ids = []

    try {
      const {toYjsState} = await import("./blocknote/convert")

      if (this.el.hasAttribute("webkitdirectory")) {
        await importFolder(this, files, {toYjsState, uploadFile})
        return
      }

      for (const file of files) {
        if (/\.zip$/i.test(file.name)) {
          await importArchive(this, file, {toYjsState, uploadFile})
        } else {
          const reply = await this.importFile(file, toYjsState)
          if (reply.id) ids.push(reply.id)
        }
      }
    } finally {
      this.js().removeAttribute(card, "aria-busy")
    }

    if (files.length === 1 && ids.length === 1) this.js().navigate(`/documents/${ids[0]}`)
  },

  async importFile(file, toYjsState) {
    const format = importFormat(file.name)
    const maxBytes = format === "docx" ? MAX_DOCX_BYTES : MAX_BYTES

    if (file.size > maxBytes) {
      return this.push("import_failed", {name: file.name, reason: "too_large", max_bytes: maxBytes})
    }

    try {
      const content = format === "docx" ? await file.arrayBuffer() : await file.text()
      const {state, fileIds, missingImages} = await toYjsState(content, format)

      return await this.push("import_document", {
        name: file.name,
        state: toBase64(state),
        file_ids: fileIds,
        missing_images: missingImages,
      })
    } catch (error) {
      console.error(error)
      return this.push("import_failed", {name: file.name, reason: "unreadable"})
    }
  },

  push(event, payload) {
    return new Promise(resolve => this.pushEvent(event, payload, reply => resolve(reply || {})))
  },
}

function importFormat(name) {
  if (/\.docx$/i.test(name)) return "docx"
  if (/\.html?$/i.test(name)) return "html"
  return "markdown"
}

