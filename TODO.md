# TODO

## Sub-documents

- **Live sidebar for other users.** When a user gains or loses access to
  documents (a member changed on an ancestor, a document moved), their sidebar
  only changes on reload: only the open document reacts. Broadcast on a
  per-user topic that their documents changed.
- **Order of siblings.** Sub-documents are sorted by creation date. Add a
  position, and drag a document above or below another, not only into it.
- **Hierarchy outside the sidebar.** Search results and the list filtered by
  a tag are flat: show the titles of the parents under each, as in the move
  panel.
- **Deleting a document by hand.** Only empty documents are deleted, never
  one with sub-documents. If added: the database deletes the descendants
  (`ON DELETE CASCADE`), but they must also leave the tantivy index; confirm
  with the number of sub-documents; tell the open DocServers.
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

## Trash

- **No automatic emptying.** Documents stay in the trash until restored or
  deleted by hand. Delete those older than e.g. 30 days, in a periodic job.
- **Restoring under a parent since deleted for good.** Impossible today: a
  sub-document goes and comes back with its parent. If a sub-document can one
  day be restored alone, put it at the root when its parent is gone.
