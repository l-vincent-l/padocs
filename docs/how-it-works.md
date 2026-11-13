# How it works

## Real-time editing

Each open document has a server process (`Yex.DocServer`) holding its Yjs
state. The browsers join it over a Phoenix channel and send their edits; the
server applies them, sends them to the others and appends them to the
document's history (`Padocs.Document.History`), compacted from time to time.
Edits made offline are kept in the browser (IndexedDB) and sent on
reconnecting; Yjs merges them without conflicts.

## Public link

From the share panel, the owner of a document gives it a public link,
`/p/<token>`: anyone with it reads the document live, without an account, but
not its sub-documents. A new link replaces the previous one; the link can be
removed. Its readers join `y_doc_public:<id>`, where the document's server
sends its updates but not the editors' awareness (their cursors and
addresses). See `PadocsWeb.PublicDocumentLive`.

## Export

From a document's "⋯" menu:

| Format | Made by |
|---|---|
| PDF | the server: the document as [Typst](https://typst.app) (`YexBlockNote.to_typst/2`), compiled by the `typst` package (a NIF) |
| Markdown, Typst | the server, from the saved snapshot |
| Word (.docx), OpenDocument (.odt) | the browser, from the editor, with BlockNote's `@blocknote/xl-docx-exporter` and `@blocknote/xl-odt-exporter` |

The server exports read the saved snapshot, which can miss the last seconds of
edits (see `Padocs.Document.YPersistence`).
