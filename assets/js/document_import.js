// Hook of the file input of a document's menu: each chosen file (Markdown, HTML,
// plain text or Word) is converted to a document by BlockNote, in the browser, and its
// Yjs state sent to the server, which creates the document. One imported file
// is opened. The BlockNote bundle is only loaded on the first import.
const MAX_BYTES = 2_000_000
// A Word file is a zip, holding its images, uploaded apart (each up to the
// server's limit, see Textexp.Files).
const MAX_DOCX_BYTES = 10_000_000

export const DocumentImport = {
  mounted() {
    this.el.addEventListener("change", () => this.importFiles([...this.el.files]))
  },

  async importFiles(files) {
    // so that choosing the same file again triggers a change
    this.el.value = ""
    if (files.length === 0) return

    const card = this.el.closest("[data-import]")
    this.js().setAttribute(card, "aria-busy", "true")
    const ids = []

    try {
      const {toYjsState} = await import("./blocknote/convert")

      for (const file of files) {
        const reply = await this.importFile(file, toYjsState)
        if (reply.id) ids.push(reply.id)
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

// btoa takes a string of bytes, built in chunks: spreading a large array at
// once would overflow the call stack.
function toBase64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  }
  return btoa(binary)
}
