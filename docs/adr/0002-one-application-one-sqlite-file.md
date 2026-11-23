# 0002. One Phoenix application next to a SQLite file

- **Status**: Accepted
- **Date**: 2026-10

## Context

[La Suite numérique's Docs](https://github.com/suitenumerique/docs) offers
the editing experience wanted (BlockNote and Yjs), but hosting it takes a
Django backend, a Next.js frontend, a Node server for the collaboration,
PostgreSQL, Redis, S3 and an OIDC provider: too much for a small team or an
association.

## Decision

Everything but the editor runs in one Phoenix application: the accounts,
the documents, the real-time sync (see [0003](0003-one-docserver-per-document.md)),
the search, the exports. The data lives in one SQLite file, which
[Litestream](https://litestream.io) can stream to S3. Each extra (S3 or
Bunny Storage, GitHub or GitLab sign-in, a remote libSQL database) is turned
on by environment variables, never required.

## Options set aside

- **PostgreSQL**: one more service to run and back up, for a load a single
  SQLite writer holds (see [performance](../performance.md)).
- **A separate Node collaboration server** (y-websocket, Hocuspocus): a
  second runtime; [y_ex](https://hex.pm/packages/y_ex) gives Yjs in Elixir.

## Consequences

- The reference deployment is one shared CPU and 512 MB, suspended when no
  one is connected.
- One instance writes: the hosts must offer a container running all the
  time, WebSockets and a persistent disk, or else an S3 for Litestream (see
  [hosts not considered](../deployment/not-considered.md)).
- Scaling past one node is not ready (see [0008](0008-no-durable-server.md)).
