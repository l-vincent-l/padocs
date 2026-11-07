# TODO

## Sub-documents

- **Order of siblings.** Sub-documents are sorted by creation date. Add a
  position, and drag a document above or below another, not only into it.
- **Hierarchy in the search.** The sidebar only shows the open document and
  its sub-documents, so documents are mostly found through the search, whose
  results are flat: show the titles of the parents under each, as in the move
  panel.
- **Live sidebar for other users.** When another user adds or moves a
  sub-document of the open document, or a user gains or loses access to
  documents (a member changed on an ancestor, a document moved), the sidebar
  only changes on reload: only the open document reacts. Broadcast on a
  per-user topic that their documents changed.
- **Performance.** Rights come from a recursive CTE, plus one query per user
  concerned on a move or a member change. Measure on large trees.

## Trash

- **No automatic emptying.** Documents stay in the trash until restored or
  deleted by hand. Delete those older than e.g. 30 days, in a periodic job.
- **Restoring under a parent since deleted for good.** Impossible today: a
  sub-document goes and comes back with its parent. If a sub-document can one
  day be restored alone, put it at the root when its parent is gone.

## Export

- **Images in the PDF.** They are links, not embedded: the server would have
  to download them, with the care that takes (only http(s), size and time
  limits, no internal addresses).
- **Up-to-date server exports.** The PDF, Markdown and Typst read the saved
  snapshot, which can miss the last seconds of edits: ask the running
  DocServer for its state, or flush it first.
- **Fonts in the Word file.** The DOCX exporter's embedded fonts (Inter,
  Geist Mono) are left out: its Buffer polyfill is missing once bundled. Embed
  them by loading the font files ourselves.
- **Accessible PDF.** The `typst` package only offers PDF/A standards, not
  PDF/UA-1, which Typst 0.15 supports.

## Import

- **Open what is imported.** An imported file becomes a document, but the
  sidebar only shows the open one: open it (the last one, for several files),
  or list them in the flash.

## Interface

- **One border style.** The search modal has thin, rounded borders; the rest
  of the app (share and move modals, the "⋯" menu, flashes, buttons) keeps
  thick borders and offset shadows.
- **Tags under the title on mobile.** Many tags take several lines: show the
  first ones, then "+N", as in the search results.
