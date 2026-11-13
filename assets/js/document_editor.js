// Hook of a document's editor element. The editor bundle (React, BlockNote,
// Yjs) is only loaded the first time a document is opened. The element's id
// changes with the document, so that LiveView replaces it when another
// document is opened: the old editor is destroyed and a new one mounted.
//
// The server's `export_document` event (`format`, `filename`) downloads the
// document as a Word or OpenDocument file, made from the editor (see
// blocknote/export.ts); `export_done` (`missing_files`, the files left out) or
// `export_failed` is sent back. The `show_version`, `hide_version` and
// `restore_version` events show a version of the document's history, from
// its Yjs state, hide it, or restore it (see blocknote.tsx).
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

    // A version of the document's history: shown read only in place of the
    // editor, hidden, or restored (its content replacing the document's),
    // `version_restored` or `restore_failed` being sent back.
    const withEditor = fun =>
      this.mounting.then(editor => {
        if (!editor) throw new Error("no editor")
        return fun(editor)
      })

    this.handleEvent("show_version", ({state}) =>
      withEditor(editor => editor.showVersion(fromBase64(state))).catch(console.error)
    )
    this.handleEvent("hide_version", () =>
      withEditor(editor => editor.hideVersion()).catch(console.error)
    )
    this.handleEvent("restore_version", () =>
      withEditor(editor => editor.restoreVersion())
        .then(() => this.pushEvent("version_restored", {}))
        .catch(error => {
          console.error(error)
          this.pushEvent("restore_failed", {})
        })
    )
  },

  destroyed() {
    this.isDestroyed = true
    this.mounting.then(editor => editor && editor.unmount())
  },
}

function fromBase64(base64) {
  return Uint8Array.from(atob(base64), c => c.charCodeAt(0))
}
