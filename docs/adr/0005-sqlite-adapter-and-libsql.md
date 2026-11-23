# 0005. ecto_sqlite3 for SQLite, ecto_hrana for libSQL

- **Status**: Accepted
- **Date**: 2026-10-21

## Context

The database first went through ecto_libsql, which silently translated the
expressions it did not handle (`exists`, `parent_as`) into a bare `?`
parameter: a policy with `exists()` was evaluated against the actor's id,
true or false depending on its first character. It also truncated binaries
at their first NUL byte.

## Decision

- **SQLite** goes through `ecto_sqlite3`, the default: a local file
  (`DATABASE_PATH`), replicated by Litestream on Fly.io.
- **A remote libSQL server** (Bunny Database) goes through `ecto_hrana`, a
  fork speaking libSQL's Hrana protocol over HTTP, chosen at compile time
  with `DATABASE_ADAPTER=hrana` (see [configuration](../configuration.md#database)).

## Consequences

- A migration rewrote as text the UUIDs ecto_libsql had stored as BLOBs; the
  `Blob` type that worked around the truncation became `:binary`.
- The adapter is a compile-time choice: an image is built for one of them.
- On libSQL, each write is an HTTP round trip, which shaped
  [0009](0009-one-writer-for-updates.md).
