# 0015. Tags in the content: an atomic inline content, kept apart from the document's tags

- **Status**: Proposed
- **Date**: 2026-11-18

## Context

Documents carry tags under their title, saying what the whole document is
about (see [concepts](../concepts.md#tags)). Following
[Logseq](https://logseq.com), tags should also go inside the text, on a
block, saying what that block is about. BlockNote's blocks nest and each
has a stable id, which this builds on.

## Decision

- **Inserted from a field, not typed.** `/` → "Tag" opens a small field at
  the cursor, offering the user's tags (`Document.search_tags/2`) as they
  type; the name may hold spaces. Enter inserts the tag chosen, or creates
  it ("Create “…”" first when it does not exist); Escape or a click elsewhere
  cancels and leaves nothing. Maybe a key shortcut too, one free in
  BlockNote and in the browsers.
- **An atomic inline content of our own**, built as BlockNote's "mentions"
  example: a chip like the title's tags, deleted at once by Backspace,
  opening the tag's page when clicked.
- **Stored per block.** On each save, the server reads the tags of each
  block (`YexBlockNote`, keeping the block ids) into a table (tag, document,
  block).
- **Apart from the document's tags.** One "budget" tag, whether under the
  title or in the text, but stored apart and never copied from one to the
  other. The search's tag filter finds both, the documents carrying it
  first, then those with it in a block, the block as snippet; the tag's page
  shows them apart. Maybe, under the title, a discreet "In the text: …",
  leaving out those already among the document's tags. Logseq does the
  same: a page's `tags::` and its blocks' `#tag` stay distinct.

## Options set aside

- **`#` as the trigger, or parsing `#tag` in typed text.** BlockNote makes a
  heading of `# ` at the start of a block, and a field taking what follows
  would break it; parsing would end tags in the wrong place, or make them by
  accident ("#1", "#fff").
- **Adding the text's tags to the document's tags.** Removing would become
  ambiguous (from the text only, or added by hand too?), the list under the
  title would grow, and the two parts of the tag's page would mix.

## Consequences

- Every export (Word, ODT, Markdown, Typst, PDF) and the import must handle
  the new inline content; Markdown writes it as in
  [0016](0016-archive-format.md).
- The tag's page, the mentions (same kind of field and inline content) and
  the deep links to blocks build on the per-block table.
