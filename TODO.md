# TODO

## Sub-documents

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

## History

Ideas from [y/hub](https://github.com/yjs/yhub), Yjs's own server (Redis,
PostgreSQL, S3: too heavy to adopt, see its API.md), to build on the
DocServer and SQLite.

- **History of a document.** Only the merged state is kept: keep snapshots
  (e.g. on each save, thinned out over time) to show the document at a past
  moment and restore it, as y/hub's activity and rollback do.
- **Named versions.** Let a user name a point of the history ("sent to the
  client"), to find it again and compare with it (y/hub's versions).
- **Suggestions.** A copy of the document where a user proposes changes,
  accepted or not by an editor, then merged: y/hub's branches.
- **Who wrote what.** y/hub's attributions (who inserted or deleted each
  piece, when) and the undo of one user's changes need Yjs 14: wait until
  yrs (y_ex) and BlockNote support it.

## Hosting and several nodes

- **Continuous backup with Litestream.** The reference hosting is one node,
  SQLite and [Litestream](https://litestream.io) streaming the database to
  S3: lose about a second on a crash, restore elsewhere (the Yjs clients
  resend their edits on reconnecting). Document it in the README, or offer it
  in the Docker image.
- **Several nodes sharing a database.** The `fusion-snapshots` branch (not
  pushed, see its README) keeps `:syn` and makes the saves conditional, merging
  the saved snapshot on a conflict: no edit lost when a partition heals.
  To do: rebase it on main (trash, order, roles reloaded by the DocServer);
  try the conditional `UPDATE` on libSQL / Bunny Database (`ecto_hrana`);
  check whether the tantivy index is per node, and share it or broadcast the
  indexing. The `durable-server` branch holds the lock-based alternative, set
  aside.
- **A Yjs log per document.** Today a document is one full snapshot,
  rewritten at most every 10 s (`YPersistence`, as y-sweet). Keep instead a
  snapshot plus the updates since, as
  [y-phoenix-channel](https://github.com/satoren/y-phoenix-channel)
  (`lib/y_phoenix/y_ecto.ex`: one row per update, compacted past 400) and
  y/hub do:
  - The DocServer appends its updates, grouped (e.g. every second, merged
    with `Yex.merge_updates`) rather than one row per keystroke as
    y-phoenix-channel, which on Bunny Database would be an HTTP round trip
    each.
  - Appending never overwrites: two DocServers of a document, on two nodes,
    cannot lose each other's edits, with no conditional write. Loading
    replays the snapshot and the updates. A crash loses at most a second.
  - Compacting folds the updates up to id N into the snapshot, then deletes
    `id <= N` (not by date: y-phoenix-channel deletes by `inserted_at`, to
    the second, which leaves duplicates, harmless to Yjs). Only that rewrite
    of the snapshot stays conditional, as in `fusion-snapshots`.
  - The updates are raw material for the history (see History): keep points
    of it instead of folding everything.
  - Still, a DocServer that only appends does not read the other node's
    updates until it reloads.

  Two possible stores, behind `YPersistence`:
  - SQLite (or libSQL): a table of updates next to `documents`. The least
    work.
  - An object store (a local folder by default, S3 if configured),
    `doc/<id>/<n>`: conditional writes (`If-None-Match`, `If-Match`) play
    the part of the conditional `UPDATE`, and the store is the backup. The
    database keeps only the relational data (users, members, tree, tags,
    trash), which does not merge. Takes a storage interface, local and S3
    adapters (Req), migrating the existing snapshots.

  Not a SQLite file per document, nor rewriting Litestream in Elixir.

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
