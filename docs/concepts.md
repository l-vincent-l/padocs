# Concepts

The rules of Padocs that using it does not always tell: who may do what, how
tags are shared, what becomes of an empty or deleted document, and what the
history keeps. How the server does it: [How it works](how-it-works.md).

## Roles and sharing

A document has three roles:

| Role | Read | Write (text, title, tags, sub-documents) | Share, move, trash |
|---|---|---|---|
| Owner | yes | yes | yes |
| Editor | yes | yes | no |
| Viewer | yes | no | no |

Whoever creates a document owns it, a sub-document included: an editor who
adds one under a shared document owns it.

**Sub-documents inherit.** A role on a document applies to all its
sub-documents, at any depth: sharing a document shares its whole tree. A user
with several roles on a document (given on it, and inherited from a parent)
has the best of them. The owner of a document is thus also owner of the
sub-documents others created under it, *by inheritance*: they may share,
move or trash them too.

**Sharing** is done by an owner, from the share panel, with someone who
already has an account, its address confirmed. The panel lists the members of
the document, and below them the accesses it inherits from its parents, which
are changed on those parents. The changes apply at once, also to the people
who have the document open: someone removed is sent away from it, someone who
becomes a viewer can no longer type.

**The public link** (see [How it works](how-it-works.md#public-link)) gives
anyone with it the right to read the document, without an account, but not
its sub-documents. Only an owner can create, renew or remove it.

## Moving and ordering

- **Under another document**: whoever can share a document (its owner, maybe
  by inheritance) can move it under a document they can write. It then
  inherits the accesses of its new parent instead of the old one's, as do its
  sub-documents: moving changes who can read them.
- **To the root**: only its owner itself, not by inheritance, since an owner
  by inheritance would lose it there.
- **Among its siblings**: whoever can write the parent can reorder its
  sub-documents (drag and drop, before or after another). The accesses do not
  change. The documents at the root have no order.

A document cannot go under itself nor under one of its sub-documents.

## Tags

- **Shared by everyone.** A tag is a label: the same label is the same tag on
  every document carrying it, whoever put it there. Case does not count:
  "Urgent" and "urgent" are one tag. A label is trimmed, its inner spaces
  collapsed, and cut at 40 characters.
- **Seen through the documents.** A user only sees the tags of the documents
  they can read: in the suggestions, the search, the most used tags.
- **Its color comes from its label**, always the same, so that it tells
  nothing about who else uses the tag.
- **Who puts them**: whoever can write a document adds or removes its tags.
  A tag no document carries any more is deleted.
- **In the search**, clicking a tag lists the documents carrying it; the tags
  offered first are those the user searched the most, then those on the most
  documents.

## Life of a document

**An empty document goes away by itself.** A document with neither title,
text nor sub-document is deleted for good a few seconds after the last person
leaves it, without going to the trash: so that "New document" leaves nothing
behind when nothing is typed. The sidebar shows it while it is open (a cross
in a dotted ring), then while it is being deleted (a ring emptying). An empty
document with sub-documents is kept.

**The trash.**

- Its owner, maybe by inheritance, puts a document in the trash, from its "⋯"
  menu; its sub-documents go with it. Nobody reads them then, members and
  public link included.
- The trash lists the documents a user owns, maybe by inheritance, deleted
  with none of their parents: a sub-document deleted along with its parent
  shows under it, not apart.
- **Restoring** a document brings back the sub-documents deleted with it, with
  their accesses. **Deleting for good** removes it, its sub-documents, their
  history and their images. The trash is never emptied automatically.
- The trash is reached from the sidebar's list (Trash) or the search's
  filters; restoring is done from either, deleting for good from the search.

## History

Every edit is kept. The history shows points of time, coarser as they age: a
minute for the last hour, an hour for the last day, a day for the last 30
days, a week before. Whoever can read a document reads its history; a point is
shown in place of the document, read only.

**Restoring** a point, by whoever can write the document, puts its text back
as a new edit, synced to everyone: nothing is lost, the state before the
restoring stays in the history. The title and the tags are not part of it.

## Working offline

The documents opened are kept in the browser (IndexedDB), so that the edits
made without a connection are kept there and sent on reconnecting; Yjs merges
them with the others' without conflicts. A document read through a public
link is not kept.

At the bottom of the screen, the state of the sync shows only when something
is wrong:

| Shown | Meaning |
|---|---|
| Offline | the connection is lost; the edits are kept on this device |
| Syncing | connected again, the missed edits being exchanged |
| The server does not answer | the document's server could not start; the page tries again by itself |
| Synced | for a moment, once all is well again |

## Finding documents

- **The sidebar** lists, as picked above it: the documents the user opened
  last (the last first, 15 at most), their own, those shared with them (the
  last updated first), or their trash.
- **The breadcrumb**, at the top of the document, gives the path to it,
  from its highest parent. Each › after a document lists that document's
  sub-documents, with "New sub-document" for those who can write it; after
  the open document, "…" lists its own sub-documents, or "+" creates the
  first one. A long path scrolls sideways.
- **The tree** of the open document, from its highest parent, shows on the
  page as a column beside the sidebar ("Show the tree on the page", in the
  breadcrumb's menus), the breadcrumb then hiding: it is the place to drag
  documents to move or reorder them. That choice, the sidebar's width and
  its folding (`Ctrl+\`) are kept in the browser.
- **The search** (the magnifier, at the top of the sidebar) looks through the
  titles, the text and the tags of the documents the user can read. On the
  right of the tags, two small buttons: ⇅ sorts the results (relevance, the
  best match first, or for the empty field the last opened; last opened;
  last modified; title), the funnel filters them (my documents, shared with
  me, trash).
