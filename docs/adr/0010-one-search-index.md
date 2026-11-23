# 0010. One search index for all documents

- **Status**: Accepted
- **Date**: 2026-11-13

## Context

Search used [Tantivy](https://github.com/quickwit-oss/tantivy) through a
fork of `tantivy_ex`, and built an index when the search opened: the first
search took 3.1 s at p95 with 20 virtual users.

## Decision

`Padocs.Document.SearchIndex` holds one index of all documents, built at
start. It indexes again, every 5 s in one commit, the documents whose title,
body or tags changed, as signalled over PubSub on each node. A search runs
in the caller's process, among the ids of the documents the user can read
(`id: IN [...]`).

## Consequences

- 40 virtual users held instead of 10; the first search takes 100 ms at p95
  with 20.
- The index lives in memory: about 9 MB for 200 documents of 1,600 words,
  57 MB for 20,000 of 200 words, plus the writer's 15 MB.
- The filter by readable ids costs about 7 µs an id: beyond some 5,000
  documents readable by one user, filter by the tree instead (ancestors and
  their owners, indexed, against the user's memberships).
- A change is searchable up to 5 s later.
