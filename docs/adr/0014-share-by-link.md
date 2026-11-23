# 0014. Share a document by link, to read or to write

- **Status**: Proposed
- **Date**: 2026-11-23

## Context

The public link (`/p/<token>`, see
[how it works](../how-it-works.md#public-link)) lets anyone read a document
live, without an account, but not its sub-documents. An owner creates,
renews or removes it. Sharing with a role takes someone who already has a
confirmed account (see [concepts](../concepts.md#roles-and-sharing)).

Two needs are not covered:

- **inviting people to write** without first asking them to create an
  account and then adding them by email;
- **finding a document again**: a signed-in user who opens a link has to
  keep the link to come back.

## Decision

To be taken. The direction considered:

1. **A link to write.** In the share panel, beside the public link, a second
   link giving the editor role, created, renewed or removed by an owner like
   the first. Removing or renewing it sends its editors away at once, as a
   removed member is (see [0006](0006-access-rights-policy-in-docserver.md)).
2. **Links received, among "Shared with me".** A signed-in user who opens a
   link, to read or to write, finds the document afterwards in "Shared with
   me". This is kept apart from the members, in a table of its own (user,
   document, link), so that renewing or removing the link takes the document
   out of their list, and the owner does not see them as members. The share
   panel might list them, as "through the link".

## Open questions

- **An account to write?**
  - *Required*: the history and the cursors say who wrote; opening the link
    signed out leads to sign-in or registration first.
  - *Not required*: a "Guest" with a name typed at the first visit; the
    instance is then open to anyone who finds the link, and the history
    names people the instance does not know.
- **Does the link reach the sub-documents?**
  - *Yes*, as a member's role does (0006): one link shares a whole tree.
  - *No*, as the public link: what is shared is exactly the page opened.
- Do links received to read also go in "Shared with me", or only those to
  write?

## Options set aside

None yet.

## Consequences

To be written once decided. Already known: the Policy gains a source of
role besides the members and the owner, and the listings filtered in SQL
(`readable_by`) must include the documents reached through a link.
