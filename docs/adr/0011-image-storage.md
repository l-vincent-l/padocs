# 0011. Images on a local folder, generic S3 or Bunny Storage

- **Status**: Accepted
- **Date**: 2026-11-13

## Context

The Word import dropped its images, and the editor could not take any.
Padocs must stay hostable without extra services
([0002](0002-one-application-one-sqlite-file.md)), yet some hosts have no
persistent disk.

## Decision

`Padocs.Files` stores the files through one of three adapters, chosen by the
environment (see [configuration](../configuration.md#storage-of-the-images)),
in this order:

1. **generic S3** (`FILES_S3_BUCKET`), signed with Req's `aws_sigv4`, with
   path-style URLs; reads are redirected to a signed URL valid 5 minutes;
2. **Bunny Storage** (`STORAGE_ZONE` and the variables Bunny sets), through
   its own API; no signed URLs, the application proxies the bytes;
3. **a local folder** (`FILES_PATH`), the default.

## Options set aside

- **An S3 adapter for Tigris only**: generic S3 covers it and the others.
- **Only S3 on Bunny**: Bunny sets its Storage variables itself, so its
  native API needs no setup.

## Consequences

- The S3 and Bunny adapters are only tested against `Req.Test` stubs.
- Images of imports never completed are deleted after an hour.
