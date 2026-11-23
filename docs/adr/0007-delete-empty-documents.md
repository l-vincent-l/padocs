# 0007. Delete empty documents when their DocServer stops

- **Status**: Accepted
- **Date**: 2026-10-14

## Context

"New document" creates a document at once; when nothing is typed, it should
leave nothing behind.

## Decision

A document with neither title, text nor sub-document is deleted for good, not
put in the trash, when its DocServer stops (in `YPersistence.unbind/3`), and
the deletion is broadcast so that the sidebars drop it. See
[concepts](../concepts.md#life-of-a-document).

## Options set aside

- **Creating the row on the first edit of the title or body**: cleaner, but
  more involved; the simpler deletion was preferred.

## Consequences

Known limits, which would make lazy creation worth another look:

- an orphan row stays when the editor never joins the channel;
- an empty document still open is deleted when the application shuts down.
