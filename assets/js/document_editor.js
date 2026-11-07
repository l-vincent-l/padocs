// Hook of a document's editor element. The editor bundle (React, BlockNote,
// Yjs) is only loaded the first time a document is opened. The element's id
// changes with the document, so that LiveView replaces it when another
// document is opened: the old editor is destroyed and a new one mounted.
//
// The server's `export_document` event (`format`, `filename`) downloads the
// document as a Word or OpenDocument file, made from the editor (see
// blocknote/export.ts); `export_done` (`missing_files`, the files left out) or
// `export_failed` is sent back.
export const DocumentEditor = {
  mounted() {
    const resolveUsers = ids =>
      new Promise(resolve =>
        this.pushEvent("resolve_users", {ids}, reply => resolve(reply.users))
      )

    this.mounting = import("./blocknote/blocknote").then(({ mountEditor }) =>
      this.isDestroyed ? null : mountEditor(this.el, {resolveUsers})
    )

    this.handleEvent("export_document", ({format, filename}) => {
      this.mounting
        .then(editor => {
          if (!editor) throw new Error("no editor")
          return editor.exportDocument(format, filename)
        })
        .then(({missingFiles}) =>
          this.pushEvent("export_done", {format, missing_files: missingFiles})
        )
        .catch(error => {
          console.error(error)
          this.pushEvent("export_failed", {format})
        })
    })
  },

  destroyed() {
    this.isDestroyed = true
    this.mounting.then(editor => editor && editor.unmount())
  },
}
