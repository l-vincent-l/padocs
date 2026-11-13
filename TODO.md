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
- **Updates of the other node.** Each document has a Yjs log
  (`Document.History`): two DocServers of a document, on two nodes, cannot
  lose each other's edits. Still, a DocServer that only appends does not read
  the other node's updates until it reloads.
- **An object store for the log.** A local folder by default, S3 if
  configured, `doc/<id>/<n>`: conditional writes (`If-None-Match`,
  `If-Match`) play the part of the conditional `UPDATE`, and the store is the
  backup. The database would keep only the relational data. Takes a storage
  interface, local and S3 adapters (Req), migrating the log.

  Not a SQLite file per document, nor rewriting Litestream in Elixir.

## Performance

From the load tests (`loadtest/`, results in its README), on 1 CPU and
512 MB as the Fly machine.

- **Search: one index per opening.** The weakest point: 10 users searching
  at once, 20 saturate the CPU (first search 3.1 s at p95, the next ones 1 s),
  with 200 documents of 1,600 words. Each opening of the search modal builds
  the user's own Tantivy index of all the documents they can read (0.5 s of
  CPU, about 7 MB), dropped when it closes. Keep it from one opening to the
  next (rebuilt when the documents change), or share one index of all the
  documents and keep the readable ones at search time (as `filter_by_tag`
  does for tags). Also measure the snippets, cut for each result.
- **Broadcast the edits of a document grouped.** The document's
  `Yex.DocServer.Worker` applies each edit and broadcasts it to everyone else
  at once (`broadcast_from`): with everyone writing, the messages grow as the
  square of the users, and 200 writers in one document saturate the CPU
  (34,000 messages a second; 100 hold, propagation 15 ms at p95). Applying an
  edit costs Yjs about 20 µs: the broadcast is the cost. Merge the edits of a
  few tens of milliseconds (`Yex.merge_updates`) into one broadcast, as the
  DocServer does for the awareness (`:flush_awareness`). The sender must
  still not get its own edit back. Measure with `loadtest/editing.exs`.
- **Joining a busy document.** With 10 writers and the others reading, 600
  users hold, but at 800 joining takes 4.5 s at p95 (propagation still
  78 ms) while 200 users join in 5 s. Suspected: each join and leave sends a
  presence diff to everyone in the document. Measure it apart, then batch or
  limit the presence of a crowded document.
- **The latency of Bunny Database.** Locally, libSQL next to the
  application is as fast as SQLite (joining 27 ms at p95 against 14 ms),
  without the network: each join reads the database several times, an HTTP
  round trip each on Bunny. Count the queries of a join, and measure against
  a copy of the Bunny deployment (not the real one).
- **Load tests on the real hosts.** Copies of the two deployments (a Fly
  app, a Magic Container with its own database), suspension off on Fly, to
  measure the network and Bunny Database; the load from a laptop or a GitHub
  Actions runner.

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
