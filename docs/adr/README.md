# Architecture decision records

Each file here records one decision that shaped Padocs: the situation, what
was chosen, what was set aside and why, and what follows from it. They keep
the reasons that the code and the commits do not tell, so that a choice can
be revisited knowingly when its reasons stop holding.

## Writing one

- Copy [template.md](template.md) to the next number,
  `NNNN-short-title.md`, and add it to the list below.
- Write it with the change it records, in English, as the rest of `docs/`.
- A record is not rewritten once accepted. When a decision changes, write a
  new record, and mark the old one `Superseded by NNNN`.
- Statuses: `Proposed`, `Accepted`, `Rejected` (an option tried and set
  aside, worth recording so that it is not tried again blindly),
  `Superseded by NNNN`.

How a feature is used belongs in the other pages of `docs/`
([concepts](../concepts.md), [how it works](../how-it-works.md)); a record
says why it is built that way, and may link to them.

## Records

| # | Decision | Status | Date |
|---|---|---|---|
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions | Accepted | 2026-11-23 |
| [0002](0002-one-application-one-sqlite-file.md) | One Phoenix application next to a SQLite file | Accepted | 2026-10 |
| [0003](0003-one-docserver-per-document.md) | Yjs and BlockNote, one DocServer per open document | Accepted | 2026-10 |
| [0004](0004-ecto-instead-of-ash.md) | Ecto written by hand instead of Ash | Accepted | 2026-10-26 |
| [0005](0005-sqlite-adapter-and-libsql.md) | ecto_sqlite3 for SQLite, ecto_hrana for libSQL | Accepted | 2026-10-21 |
| [0006](0006-access-rights-policy-in-docserver.md) | Access rights in one Policy, held live by the DocServer | Accepted | 2026-10-26 |
| [0007](0007-delete-empty-documents.md) | Delete empty documents when their DocServer stops | Accepted | 2026-10-14 |
| [0008](0008-no-durable-server.md) | Keep :syn, not durable_server, to place DocServers | Rejected | 2026-11-06 |
| [0009](0009-one-writer-for-updates.md) | One process writes the updates of all documents | Accepted | 2026-11-10 |
| [0010](0010-one-search-index.md) | One search index for all documents | Accepted | 2026-11-13 |
| [0011](0011-image-storage.md) | Images on a local folder, generic S3 or Bunny Storage | Accepted | 2026-11-13 |
| [0012](0012-gettext-english-msgids.md) | Interface through Gettext, English msgids, French by default | Accepted | 2026-11-13 |
| [0013](0013-generic-code-in-own-namespaces.md) | Generic code kept in YPhoenix and YexBlockNote, not published | Accepted | 2026-10-13 |
