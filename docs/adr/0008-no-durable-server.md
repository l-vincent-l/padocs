# 0008. Keep :syn, not durable_server, to place DocServers

- **Status**: Rejected
- **Date**: 2026-11-06

## Context

To keep the option of running several nodes, the hex package
`durable_server` was tried to host DocServers, with one owner per document
across a cluster and failover (branch `durable-server`, not merged).

## Decision

Set aside: DocServers stay registered with :syn
([0003](0003-one-docserver-per-document.md)). On one node,
`durable_server` costs more than it brings:

- two SQL writes per save instead of one;
- a background heartbeat load;
- a failover of about 30 s, against an immediate one with :syn;
- a reliance on undocumented APIs (`Yex.DocServer.Worker`,
  `DurableServer.StorageBackend`, both `@moduledoc false`).

An alternative was tried on branch `fusion-snapshots` (not merged): keep
:syn, make the saves conditional on `updated_at`, and merge the snapshot in
the database on conflict, since Yjs states merge. A test of two partitioned
nodes on one SQLite file lost no edit.

## Consequences

- `durable_server` is only worth it for state that cannot be merged, or
  side effects that must happen once; Yjs documents are neither.
- To resume multi-node, start from the README of `durable-server` ("To
  resume it") and from `fusion-snapshots`.
