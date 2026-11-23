# 0001. Record architecture decisions

- **Status**: Accepted
- **Date**: 2026-11-23

## Context

The reasons behind Padocs' structure were spread across commit messages
(in French), the TODO, branch READMEs (`durable-server`, `fusion-snapshots`)
and the performance page. Someone revisiting a choice had to dig for why it
was made, and options already tried and set aside risked being tried again.

## Decision

Keep architecture decision records in `docs/adr/`, one numbered file per
decision, following [the template](template.md). The first ones were written
afterwards, from the history, for the decisions already taken.

## Consequences

- A new structural choice ships with its record, in the same change.
- Records already accepted are not edited but superseded, so the history of
  the reasoning stays readable.
- The retroactive records are only as precise as the commits and notes they
  come from; their dates are those of the commits.
