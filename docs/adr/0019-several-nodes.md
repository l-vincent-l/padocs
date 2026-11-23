# 0019. Several nodes: conditional saves, then the Yjs log in an object store

- **Status**: Proposed
- **Date**: 2026-11-23

## Context

Padocs runs on one node ([0002](0002-one-application-one-sqlite-file.md)).
`durable_server` was set aside to place DocServers across nodes
([0008](0008-no-durable-server.md)). Each document has a Yjs log
(`Document.History`): two DocServers of a document, on two nodes, cannot
lose each other's edits; but one that only appends does not read the other
node's updates until it reloads. The search index is already per node, its
changes broadcast to every node (`SearchIndex.changed/1`).

## Decision

1. **First, the `fusion-snapshots` branch**: keep `:syn`, make the saves
   conditional, and merge the saved snapshot on a conflict; no edit is lost
   when a partition heals. To do: rebase it on main, and try the conditional
   `UPDATE` on libSQL / Bunny Database (`ecto_hrana`).
2. **Then, an object store for the log**: a local folder by default, S3 if
   configured, at `doc/<id>/<n>`. Conditional writes (`If-None-Match`,
   `If-Match`) play the part of the conditional `UPDATE`, and the store is
   the backup; the database keeps only the relational data. It takes a
   storage interface with local and S3 adapters (Req), and migrating the
   log.

## Options set aside

- **A SQLite file per document.**
- **Rewriting Litestream in Elixir.**
- **`durable_server`** (see [0008](0008-no-durable-server.md)).

## Consequences

- Hosts that overlap their deploys could use the same kind of lock in the
  bucket, taken at start by a conditional write, for Litestream.
- A DocServer still has to learn of the other node's updates without
  reloading.
