# 0003. Yjs and BlockNote, one DocServer per open document

- **Status**: Accepted
- **Date**: 2026-10

## Context

Several people edit a document at once, possibly offline, and their edits
must merge without conflicts.

## Decision

The browser edits with [BlockNote](https://www.blocknotejs.org) over a
[Yjs](https://yjs.dev) document. On the server, each open document has one
process, a `YPhoenix.DocServer` (built on y_ex), that holds its Yjs state,
relays the updates between the Phoenix channels of its editors, and saves
them through a persistence behaviour. DocServers are registered with
[:syn](https://hex.pm/packages/syn) in the `doc_servers` scope, so that a
document has one server across connected nodes. A DocServer stops a short
while after its last editor leaves.

## Consequences

- Edits merge as CRDT updates: offline edits kept in the browser merge when
  the connection comes back.
- The server can read the document (export, search, excerpts) from the Yjs
  state, through `YexBlockNote` (see [0013](0013-generic-code-in-own-namespaces.md)).
- BlockNote's schema is read on the server: a change of schema in a
  BlockNote release can break the readers.
