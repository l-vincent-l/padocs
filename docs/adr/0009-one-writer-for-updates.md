# 0009. One process writes the updates of all documents

- **Status**: Accepted
- **Date**: 2026-11-10 (merged 2026-11-13)

## Context

With the Yjs log and the history, each DocServer wrote its updates about
once a second and waited for the write. Under load (see
[performance](../performance.md)), that made 250 writes a second at 1,250
virtual users; on libSQL each is an HTTP round trip through a pool of 10
connections, and the DocServers ended up waiting for the pool.

## Decision

The DocServers hand their updates to `Padocs.Document.UpdateWriter` without
waiting. It appends those of all documents in one multi-row `INSERT` about
once a second, and writes what is left at shutdown, after the DocServers. A
failed write is logged and retried at the next one.

## Consequences

- SQLite holds 1,500 virtual users (300 documents), its limit becoming
  memory; libSQL holds the 1,000 tried with a propagation p95 of 2 ms.
- An update is in memory for up to about a second before reaching the
  database.
- The DocServers still wait for the excerpt (every 10 s) and the compaction
  (every 60 updates).
