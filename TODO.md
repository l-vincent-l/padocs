# TODO

## Sub-documents

- **Hierarchy in the lists.** The search results and the sidebar's lists
  (my documents, shared with me, recent) are flat: show the titles of the
  parents under each, as in the move panel.
- **Live sidebar for other users.** When another user adds or moves a
  sub-document of the open document, or a user gains or loses access to
  documents (a member changed on an ancestor, a document moved), the
  sidebar's lists and the tree of sub-documents only change on reload: only
  the open document reacts. Broadcast on a per-user topic that their
  documents changed.
- **Performance.** Rights come from a recursive CTE, plus one query per user
  concerned on a move or a member change. Measure on large trees.

## History

Ideas from [y/hub](https://github.com/yjs/yhub), Yjs's own server (Redis,
PostgreSQL, S3: too heavy to adopt, see its API.md), to build on the
DocServer and SQLite.

- **Named versions.** Let a user name a point of the history ("sent to the
  client"), to find it again and compare with it (y/hub's versions).
- **Suggestions.** A copy of the document where a user proposes changes,
  accepted or not by an editor, then merged: y/hub's branches.
- **Who wrote what.** y/hub's attributions (who inserted or deleted each
  piece, when) and the undo of one user's changes need Yjs 14: wait until
  yrs (y_ex) and BlockNote support it.

## Hosts to try and document

Each has a page in `docs/deployment/`, marked not tried, with what we know:
try it, then make it a guide (or drop it, in `not-considered.md`). What a
host must give: "Choosing a host" in `docs/deployment/README.md`. The offers
change often: check them when trying.

- **Railway** (`railway.md`): how it deploys with a volume.
- **Koyeb** (`koyeb.md`): what its volumes allow, first.
- **Clever Cloud** (`clever-cloud.md`): the `fly` image with Litestream at
  start, to Cellar; first, whether its deploys overlap.
- **Scaleway Serverless Containers** (`scaleway.md`): the same, to its
  Object Storage; whether its deploys overlap, the restore at wake-up.
- **Litestream at start** (`litestream.md`, "Without a persistent disk"):
  if a host overlaps its deploys, a lock in the bucket taken at start by a
  conditional write, as for "Several nodes" below.
- **A bare machine at a cloud** (`bare-machine.md`): `cloud-init.yaml` was
  tried in a local virtual machine only (Debian 13, Caddy's own
  certificates). Still to try at a cloud, with Let's Encrypt and the
  host's S3 for Litestream; and on Ubuntu 24.04 (Podman 4.9).
- **A bare machine without containers.** First, **a release built by a
  workflow**: a `.tar.gz` for Debian 13, amd64 and arm64, published with
  each version (a GitHub release). On the machine, neither Elixir nor
  Node: the archive unpacked in `/opt/padocs`, a systemd unit
  (`bin/migrate`, then `bin/server`, as a user of its own, a stop timeout
  for the last saves), Caddy in front. A cloud-init file too, as
  `cloud-init.yaml`; Litestream as a binary with its own unit. The same
  workflow serves the YunoHost package below.
- **Then, as an annex, built on the machine**, from the sources: Erlang and
  Elixir from `mise` (Debian's are too old: Elixir 1.18, OTP 27), Node and
  npm for the assets (the NIFs of Tantivy, Yex and Typst come precompiled), then `mix assets.deploy` and `mix release`. The versions
  follow the `Dockerfile`'s. Its costs, to state: about 2 GB of memory and a
  quarter of an hour on 2 virtual CPUs to build, the compilers on the
  server, updates by hand (pull, build, restart) without going back to the
  previous version when the new one fails.
- **A YunoHost package** (`yunohost.md`): `padocs_ynh`, with a release per
  architecture built by a workflow (the one above).
- **Let's Encrypt on Dokku**: the plugin was not tried (it needs a public
  domain); HTTPS was tried with a self-signed certificate.

## Hosting and several nodes

- **Several nodes sharing a database.** The `fusion-snapshots` branch (not
  pushed, see its README) keeps `:syn` and makes the saves conditional, merging
  the saved snapshot on a conflict: no edit lost when a partition heals.
  To do: rebase it on main (trash, order, roles reloaded by the DocServer);
  try the conditional `UPDATE` on libSQL / Bunny Database (`ecto_hrana`).
  The search index is already per node, its changes broadcast to every node
  (`SearchIndex.changed/1`). The `durable-server` branch holds the lock-based
  alternative, set aside.
- **Updates of the other node.** Each document has a Yjs log
  (`Document.History`): two DocServers of a document, on two nodes, cannot
  lose each other's edits. Still, a DocServer that only appends does not read
  the other node's updates until it reloads.
- **An object store for the log.** A local folder by default, S3 if
  configured, `doc/<id>/<n>`: conditional writes (`If-None-Match`,
  `If-Match`) play the part of the conditional `UPDATE`, and the store is the
  backup. The database would keep only the relational data. Takes a storage
  interface, local and S3 adapters (Req), migrating the log.

  Not a SQLite file per document, nor rewriting Litestream in Elixir (see
  `docs/adr/0019-several-nodes.md`).

## Performance

From the load tests (`loadtest/`, results in `docs/performance.md`), on 1 CPU and
512 MB as the Fly machine.

- **Search: the snippets.** With one index of all the documents, 40 users
  searching at once hold, 60 saturate the CPU, with 200 documents of 1,600
  words. Of the 34 ms of a search, the 20 snippets take about 20: Tantivy's
  generator goes through the whole body of each (0.5 µs a word). Cut them
  from a bounded part of the body, around the first words found, or only
  for the results shown.
- **Search: filter by the tree.** A search keeps the documents the user can
  read by their ids, about 7 µs each: 65 ms at 10,000. Past some thousands
  of readable documents, index the ids of each document's ancestors and
  their owners, and filter by the user's memberships and their own id; a
  move then indexes the moved documents again.
- **Search: the index at start.** `SearchIndex` builds the index of all the
  documents at each start, in native memory (9 MB for 200 documents of
  1,600 words, 57 MB for 20,000 of 200 words): until it is done, searches
  find fewer documents. A document deleted with its parent stays in it until
  the next start, never found. Measure the build on many documents; past
  that, keep the index on disk.
- **Broadcast the edits of a document grouped.** The document's
  `Yex.DocServer.Worker` applies each edit and broadcasts it to everyone else
  at once (`broadcast_from`): with everyone writing, the messages grow as the
  square of the users, and 200 writers in one document saturate the CPU
  (34,000 messages a second; 100 hold, propagation 15 ms at p95). Applying an
  edit costs Yjs about 20 µs: the broadcast is the cost. Merge the edits of a
  few tens of milliseconds (`Yex.merge_updates`) into one broadcast, as the
  DocServer does for the awareness (`:flush_awareness`). The sender must
  still not get its own edit back. Measure with `loadtest/editing.exs`.
- **Joining a busy document.** With 10 writers and the others reading, 600
  users hold, but at 800 joining takes 4.5 s at p95 (propagation still
  78 ms) while 200 users join in 5 s. Suspected: each join and leave sends a
  presence diff to everyone in the document. Measure it apart, then batch or
  limit the presence of a crowded document.
- **The latency of Bunny Database.** Locally, libSQL next to the
  application is as fast as SQLite (joining 27 ms at p95 against 14 ms),
  without the network: each join reads the database several times, an HTTP
  round trip each on Bunny. Count the queries of a join, and measure against
  a copy of the Bunny deployment (not the real one).
- **Load tests on the real hosts.** Copies of the two deployments (a Fly
  app, a Magic Container with its own database), suspension off on Fly, to
  measure the network and Bunny Database; the load from a laptop or a GitHub
  Actions runner.

## Trash

- **No automatic emptying.** Documents stay in the trash until restored or
  deleted by hand. Delete those older than e.g. 30 days, in a periodic job.
- **Restoring under a parent since deleted for good.** Impossible today: a
  sub-document goes and comes back with its parent. If a sub-document can one
  day be restored alone, put it at the root when its parent is gone.

## Archive

- **Archive a document.** From its menu, beside "Move to trash": the
  document leaves the sidebar's lists (my documents, shared with me, recent)
  and the search by default, but stays readable by its members and at its
  links, never deleted, unlike the trash. It goes with its sub-documents, as
  to the trash. An "Archived" list in the sidebar, as the trash's, gives it
  back ("Unarchive"); the search finds it with a filter. To decide first:
  whether an archived document becomes read only (the DocServer refusing
  edits, as for a reader) or stays editable, only hidden; who may archive
  it (its owners, or its editors too); and whether archiving concerns every
  member or only the user, as a personal "hide from my lists".

## Files

- **Metadata of images.** The bytes are stored as uploaded, EXIF included
  (a photo's GPS position, the camera, the date), readable by every reader
  of the document, or by anyone with its public link. Strip it on upload:
  for JPEG, drop the APP1 segments without decoding the image; for PNG and
  WebP, their `eXIf`/`EXIF` chunks.
- **Copy the external images of an import.** An imported file's
  `![](https://…)` stays an external link: each reader then loads it from a
  third party, which sees their address (a tracking pixel), and the image
  goes when the site removes it. Download them on the server during the
  import (the browser cannot, most sites refusing CORS), into
  `Padocs.Files`, and tell the user in the closing message ("12 external
  images copied, 2 not reachable"). Guarded against SSRF: only http(s),
  the host resolved once and refused when private, loopback or link-local
  (no internal services, no cloud metadata), the request made to the IP
  resolved (no DNS rebinding), redirects checked again, a size limit and a
  timeout, the type checked by its bytes as for an upload. Maybe for images
  pasted by URL in the editor too. See `docs/adr/0018-copy-external-images.md`.
- **Images removed from a document** stay stored until the document is
  deleted for good: its history may still show them. Delete those no
  version refers to, when the history is compacted.
- **Against real services.** `S3Storage` and `BunnyStorage` are only
  tested against stubs (`Req.Test`): try them on Tigris, a MinIO and the
  Bunny Storage zone.
- **Bunny Storage sends the bytes through the application**, its API having
  no signed URLs: serve them by a pull zone with token authentication, when
  the images get many.

## Export

- **Images in the PDF.** They are links, not embedded. Those stored by
  `Padocs.Files` could be read from the storage and embedded; the others
  would have to be downloaded, with the care that takes (only http(s), size
  and time limits, no internal addresses).
- **Up-to-date server exports.** The PDF, Markdown and Typst read the saved
  snapshot, which can miss the last seconds of edits: ask the running
  DocServer for its state, or flush it first.
- **Fonts in the Word file.** The DOCX exporter's embedded fonts (Inter,
  Geist Mono) are left out: its Buffer polyfill is missing once bundled. Embed
  them by loading the font files ourselves.
- **Accessible PDF.** The `typst` package only offers PDF/A standards, not
  PDF/UA-1, which Typst 0.15 supports.
- **Export all of a user's documents.** From the preferences: a zip of the
  documents they own, as folders following the tree, each document in
  Markdown with its images. Each file starts with a YAML front matter
  (`title`, `tags`, `id`, `created`, `updated`), the convention of
  Obsidian, Hugo or Jekyll: the archive is usable elsewhere, a file keeps
  its tags when moved alone, and tags may hold spaces (quoted). No separate
  tags file, read by no other tool. A manifest (JSON) gives what the front
  matter does not: the parents by id, the order of the sub-documents, the
  path of each Yjs state; importing a Padocs archive, it prevails. Tags in
  the content (see Tags and blocks) are written `#tag`, or `#[[two words]]`
  as Logseq, not in the front matter, which holds the document's own. Maybe
  the Yjs state of each document too, to import it again without loss
  (Markdown loses some blocks and styles). Built in a background task, the user getting a link
  (or an email) when it is ready: an account may hold thousands of
  documents. Those shared with them stay out, or as an option. The format
  and its reasons: `docs/adr/0016-archive-format.md`.
- **Export a whole instance.** Hesitating. The documents are not encrypted:
  whoever runs the server can already read them all, in the database, so an
  export adds no access. Rather than a page (there is no administrator role
  in the application), a release command (`bin/padocs eval`, or a Mix task)
  writing one archive per user, in the format above, to move to another
  Padocs, or away. For a mere backup, the database (Litestream, a copy of
  the SQLite file) and the files' storage are enough.

## Import

- **Open what is imported.** An imported file becomes a document, listed in
  "My documents" but neither opened nor among the recent ones: open it (the
  last one, for several files), or list them in the flash.
- **Import a Padocs archive.** With the export of all of a user's documents
  (see Export), its manifest gives back the tree, the order, the tags, the
  Yjs state when there, in place of what the paths tell.
- **Import on the server.** In a background task, the tab free to close: the
  server would need its own Markdown and HTML parser writing BlockNote's
  Yjs structure, and would not read Word files. Worth it for very large
  archives only.
- **Progress of an archive or folder import.** Importing a zip or a folder
  only sets `aria-busy` on the new-document button (a small spinner in place
  of the chevron): show how many documents have been imported out of the
  plan, and let the user cancel.

## Tags and blocks (from Logseq)

Ideas from [Logseq](https://logseq.com), where tags and links point to
blocks, not only to pages. BlockNote has nested blocks (Tab indents a block
under the previous one: its `children`, read by `YexBlockNote.to_blocks/1`),
and each block has a stable id (the `id` of its `blockContainer`), which
these build on. The choices for the tags in the content are in
`docs/adr/0015-tags-in-the-content.md`.

- **Tags in the content.** `/` → "Tag" opens a small field at the cursor, as
  the link's, offering the user's tags (`Document.search_tags/2`) as they
  type. The name is typed there, not in the text, so it may hold spaces:
  Enter inserts the tag chosen, or creates it ("Create “…”" first when it
  does not exist), Escape or a click elsewhere cancels and leaves nothing.
  Not `#` as a shortcut: BlockNote makes a heading of `# ` at the start of
  a block, and a field taking what follows would break it. Maybe a key
  shortcut instead, one free in BlockNote and in the browsers.
  The tag is then a custom inline content, atomic: a chip like the title's
  tags, deleted at once by Backspace, opening the tag's page when clicked.
  Built as the "mentions" example of BlockNote's documentation: an inline
  content of our own and a suggestion menu opened on a character. No parsing of `#tag` in typed text, so no tag
  ending in the wrong place nor made by accident ("#1", "#fff"). Every
  export (Word, ODT, Markdown, Typst, PDF) and the import must handle it.
  On each save, the server reads the tags of each block (`YexBlockNote`,
  keeping the block ids) and stores them in a table (tag, document, block).

  A tag in the text is not added to the document's tags (under the title):
  those say what the whole document is about, a tag in a block what that
  block is about. Copying them would make removing ambiguous (from the text
  only, or added by hand too?), lengthen the list under the title, and mix
  the two parts of the tag's page. They are the same tags (one "budget",
  whether under the title or in the text), stored apart: the search's tag
  filter finds both, the documents carrying it first, then those with it in
  a block, the block as snippet; the tag's page shows them apart. Maybe,
  under the title, a discreet "In the text: budget, client", leading to the
  blocks, without those already among the document's tags. Logseq does the
  same: a page's `tags::` and the `#tag` of its blocks stay distinct.
- **A page per tag, first the list.** The documents carrying the tag, then
  the blocks carrying it, each with its sub-blocks (read only) and a link to
  its document; only those the user can read. Reached from a tag anywhere
  (the title's tags, the search, a tag in the text).
- **Then the tag's small document**, at the top of its page, to describe the
  tag: a document attached to the tag, edited like the others. To decide
  first: who owns it and who can edit it, the tags being shared by everyone
  who sees the documents carrying them.
- **A page of the mentions of a person**, as the tag's list: the documents
  and the blocks mentioning them (see Mentions below), only those the reader
  can read; "my mentions" from the sidebar.
- **Deep links to blocks.** Copy a block's link (its menu, beside the drag
  handle): `/documents/<id>#<block id>` opens the document scrolled to the
  block, highlighted. Then a page of the block, editing it and its
  sub-blocks only. The hard part: BlockNote and y-prosemirror bind an editor
  to a whole `Y.XmlFragment`, not to one block of it. Try an editor whose
  changes are applied to the block's subtree in the document's Y.Doc, both
  ways, or a full editor hiding the other blocks; first, the tag page and
  the block page could show the blocks read only, with a link to edit them
  in their document.
- **References.** Logseq's `((block))` embeds a block in another, edited in
  either place; `[[page]]` links a document, and the linked page lists the
  references to it (backlinks). After the block pages, if they hold.

## Mentions

- **Mention a person.** `/` → "Mention", or `@`, opens the same kind of
  field as the tags (see Tags and blocks), offering the people who can read
  the document. The mention is an atomic inline content too, showing the
  person's name, with the same parts as the tags (BlockNote's "mentions"
  example). Every export and the import must handle it. On each save, the
  server stores the mentions in a table (user, document, block), for the
  page of the mentions of a person.
- **Notify the person mentioned**, later: in Padocs, or by email (the emails
  of Padocs, see docs/deployment), once per mention, not on every save.

## Sharing

The public link (`/p/<token>`, see `docs/how-it-works.md`) gives the right
to read only, without an account.
The choices below are open in `docs/adr/0014-share-by-link.md`.

- **A link to write.** From the share panel, beside the public link, a
  second link giving the role of editor, renewed or removed by an owner as
  the first. To decide first: whether it needs an account (the history and
  the cursors then say who wrote; without one, a "Guest" with a name typed
  at the first visit, and an instance open to anyone who finds the link),
  and whether it reaches the sub-documents, as a member's role does, or not,
  as the public link. Removing it sends its editors away at once, as a
  member removed.
- **A link received among the documents shared with me.** A signed-in user
  opening a link (to read or to write) finds the document afterwards in
  "Shared with me", without keeping the link. Kept apart from the members
  (a table user, document, link), so that renewing or removing the link
  takes it out of their list, and the owner does not see them as members.
  Maybe the share panel lists them, as "through the link".

## Administration

Anyone may register today, and there is no administrator role in the
application, only the LiveDashboard's credentials (`DASHBOARD_USER`). Every
way to register counts in the items below, the password, the sign-in link
and GitHub alike.

- **An administrator role, first.** The items below need it. Defined by a
  variable, `ADMIN_EMAILS` (addresses separated by commas), checked on each
  request: an account is administrator while its address is in it **and
  confirmed**, so that registering first with that address, without
  receiving its emails, gives nothing. Not the first account registered: on
  a new instance, it would go to whoever comes first. Removing an address
  from the variable removes the role at the next restart. Maybe later a page
  to name other administrators, kept in the database, the variable still
  giving the first ones. The administrator gets an "Administration" entry in
  the menu, and the LiveDashboard without its own credentials. See
  `docs/adr/0017-administrator-role.md`.
- **Control the opening of registrations.** Open, by invitation only, or
  closed, set by the administrator on a page of their own (kept in the
  database, a default from a variable). Closed, the registration page says
  so and the sign-in by link or by GitHub creates no account.
- **Invitations.** The administrator (maybe any member, as an option)
  invites an address: an email with a link, used once, expiring after some
  days, registering even when registrations are closed. Listed on the page,
  sent again or revoked. Maybe sharing a document with an address without
  account becomes an invitation too.
- **Approval of registrations.** Apart from the confirmation of the
  address, already done (the email within 7 days): a new account waits for
  the administrator's approval before using Padocs, a page listing those
  waiting, an email to each when approved; the administrator told of each
  new one.
- **Allowed email domains.** Registrations only for the addresses of some
  domains (`example.org`, maybe its subdomains), the others refused at once,
  or put to the approval above. Checked at the registration, on an address
  changed, and on the GitHub sign-in, on its verified address.

## Interface

- **Remember the sidebar's list.** The list picked (recent, my documents,
  shared with me, trash) goes back to the recent documents on reload, or
  when the open document goes to the trash: keep it in the browser, as the
  folding of the menu.
- **Focus on the title of a new document.** On "New document" (or a new
  sub-document), the cursor goes to its title, to type it at once, then
  Enter goes on to the text; an opened existing document keeps the focus as
  today.
- **Tags under the title on mobile.** Many tags take several lines: show the
  first ones, then "+N", as in the search results.
- **Table of contents of a document.** The headings of the open document, a
  click scrolling to one, the one being read marked as the page scrolls. In
  the right margin on a wide screen, a short line per heading (longer for a
  higher level), unfolding into the titles when pointed at or focused, as
  Notion does; on a narrow one, a button in the top bar opening it as a
  panel. Only for the open document, read live from the editor (BlockNote's
  blocks, updated as anyone edits), with nothing from the server; shown from
  two or three headings. The links to a heading could then come from it
  (copy the link of a heading).
- **Document actions button turns blank when open.** `#document-actions-button`
  sets `aria-expanded:bg-primary aria-expanded:text-primary-content`, but the
  button's background stays `bg-base-100`, making the `…` icon invisible while
  the menu is open.
- **Sub-documents tree in the sidebar.** Pinning `#tree-panel` is hidden
  inside a breadcrumb popover (unavailable when a document has neither parent
  nor child), adds a second 256 px column on large screens, and pushes the
  document down on mobile. Offer the open document's tree directly inside the
  sidebar instead of a second column.
- **Filter in the move modal.** `#move-modal` lists every writable
  destination without filtering, which does not scale to large trees or
  imported vaults: add a search field at the top of the list.
- **Multi-line document title.** `#document-title` is a single-line `<input>`,
  so even short titles (~30 chars on desktop, ~15 on mobile) clip sideways
  instead of wrapping (unlike the public page's `<h1>`): use an auto-growing
  `<textarea>`.
- **Reading margins and metadata row on mobile.** `px-[54px]` on the document
  header and skeleton (and in `PublicDocumentLive`) takes 108 px of horizontal
  padding on narrow screens: reduce it on small viewports. Under the title on
  mobile, tags, the wrapped date, and `#viewers` split onto up to four lines
  (leaving the avatar alone on the last line), and the always-visible tag `×`
  buttons sit very close to the clickable tag labels.
- **Local dates and times.** Timestamps (`#last-update`, history, version
  banner, search cards, trash) are shown in raw UTC: format them in the
  browser's timezone (and optionally as relative time with the exact date in
  `title`).
- **Empty document deletion notice.** The countdown icon (`deletion_mark`)
  only shows in `#tree-panel`, which is hidden by default: an empty document
  left briefly can disappear without the user seeing why. Show the mark in
  the sidebar's lists too, or explain it discreetly while the empty document
  is open.
- **Dark theme in BlockNote and matching topbar.** `blocknote.tsx` passes
  `theme="light"` unconditionally to `<BlockNoteView>` (leaving some Mantine
  and native controls in light scheme in dark mode), and `topbar` in `app.js`
  still uses Phoenix's default `#29d` cyan instead of the theme's
  `--color-primary`.
- **Replace native `data-confirm` dialogs.** Destructive actions (trash,
  purge, empty trash, remove member, regenerate/disable public link, restore
  version) use `window.confirm()`, breaking the visual style. Use a styled
  confirmation modal for irreversible actions, and make "Put in the trash" an
  immediate action with an "Undo" button in the flash.
- **Collaborator identity.** `#viewers` and `#members` only show the first
  letter of the email, and the editor's cursor color (`myColor` in
  `blocknote.tsx`) is random per load and does not match the header avatar:
  derive a stable color per user and align avatar and cursor colors.
- **Sign-in page simplification, duplicate email ID and header spacing.**
  `/sign-in` stacks two separate email inputs (`#password-sign-in` and
  `#magic-link`) that both render `@form[:email]`, producing duplicate DOM
  `id`s: fix the duplicate IDs and simplify the layout (one email field or
  tabs for password vs. sign-in link). Also use a non-breaking space before
  `?` in French ("Pas encore de compte ?") so it does not wrap onto an
  orphan line, hide the redundant "Sign in" link in the navbar on `/sign-in`,
  and give the unauthenticated mobile header breathing room between the logo
  and "Sign in".
- **Share modal public link and "(you)" label.** In `#share-modal`, the public
  URL input and its three action buttons share one row, truncating the URL;
  in inherited accesses, `(you)` has no leading space and disappears when a
  long email truncates.
- **Auto-dismiss info flashes.** Info toasts ("Signed in", "Public link
  created") stay pinned in the bottom-right corner until clicked: dismiss
  non-error flashes automatically after a few seconds (pausing on hover, or
  keeping those with an action link).
- **Modal focus trap and menu keyboard navigation.** Dialogs (`SearchModal`,
  `#move-modal`, `#share-modal`, `#history-panel`) lack a Tab focus trap and
  do not restore focus to their trigger on close; `#document-actions-menu`
  declares `role="menu"` without `↑`/`↓` arrow navigation, and
  `#new-document-more` / `#sidebar-scope-button` do not toggle
  `aria-expanded`.
- **Typography contrast and weight.** `DM Mono` at `font-weight: 300` in
  `text-xs` with `/60` or `/50` opacity can look thin and low-contrast on
  non-Retina screens and in dark mode: review small muted text contrast and
  weights.
