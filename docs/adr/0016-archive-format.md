# 0016. Archive of a user's documents: Markdown with front matter, and a manifest

- **Status**: Proposed
- **Date**: 2026-11-23

## Context

A user should be able to take all of their documents away, to another
Padocs or to another tool, and to bring a Padocs archive back without loss.
The import already reads folders and zips of Markdown, HTML, text and Word
files (Obsidian vaults, Logseq graphs, Notion exports), where the paths give
the tree.

## Decision

- **The export**, from the preferences: a zip of the documents the user
  owns, as folders following the tree, each document in Markdown with its
  images. Those shared with them stay out, or come as an option.
- **A YAML front matter** at the start of each file: `title`, `tags`, `id`,
  `created`, `updated`, the convention of Obsidian, Hugo and Jekyll. Tags
  may hold spaces, quoted.
- **The tags in the content** ([0015](0015-tags-in-the-content.md)) are
  written `#tag`, or `#[[two words]]` as Logseq does, in the text; the front
  matter holds only the document's own.
- **A JSON manifest** gives what the front matter does not: the parents by
  id, the order of the sub-documents, the path of each Yjs state. Importing
  a Padocs archive, it prevails over what the paths tell.
- Maybe **the Yjs state** of each document too, to import it again without
  loss, as Markdown loses some blocks and styles.
- **Built in a background task**, the user getting a link (or an email)
  when ready: an account may hold thousands of documents.

## Options set aside

- **A separate tags file**: no other tool would read it, and a file moved
  alone would lose its tags.
- **Importing on the server**, in a background task: it would need a
  Markdown and HTML parser of our own writing BlockNote's Yjs structure, and
  would not read Word files. The import stays in the browser; the server
  import is worth it for very large archives only.

## Consequences

- The archive is usable elsewhere as plain Markdown, and complete for
  Padocs through the manifest.
- Exporting a whole instance, still undecided, would write one such archive
  per user.
