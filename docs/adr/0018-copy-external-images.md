# 0018. Copy an import's external images on the server, guarded against SSRF

- **Status**: Proposed
- **Date**: 2026-11-23

## Context

An imported file's `![](https://…)` stays an external link: each reader then
loads it from a third party, which sees their address (a tracking pixel),
and the image goes when the site removes it. The browser cannot download
them itself: most sites refuse CORS.

## Decision

The server downloads them during the import into `Padocs.Files`
([0011](0011-image-storage.md)), and the closing message tells the user
("12 external images copied, 2 not reachable"). The download is guarded:

- only `http` and `https`;
- the host resolved once, and refused when private, loopback or
  link-local: no internal services, no cloud metadata;
- the request made to the IP resolved, against DNS rebinding;
- each redirect checked again;
- a size limit and a timeout;
- the type checked by its bytes, as for an upload.

Maybe for images pasted by URL in the editor too.

## Consequences

- The server makes requests chosen by users: the guards above are what keep
  it from reaching its own network, and must be tested as such.
- The same guarded download would serve the images embedded in the PDF
  export.
