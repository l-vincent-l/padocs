# Deployment on Clever Cloud

> **Not tried yet.** What we know of Clever Cloud, before trying it;
> nothing here was deployed. Still to do: see the
> [to do](../../TODO.md#hosts-to-try-and-document).

What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

[Clever Cloud](https://www.clever-cloud.com) (French) runs Docker
applications, with an S3 of its own, Cellar. The best candidate among the
hosts without a persistent disk.

## No disk for SQLite

Its persistent storage, FS Buckets, is a network file system: to avoid for
SQLite, whose locks and WAL need a local disk. The container's own disk is
local, but erased on each restart.

## What we expect

- The `fly` target of the `Dockerfile`, with Litestream: it restores the
  database from Cellar when the disk is empty, then streams every write to
  it (see [Litestream](litestream.md#without-a-persistent-disk), and its
  conditions).
- The images in Cellar too (`FILES_S3_BUCKET`), so that everything stays
  with one provider, without libSQL.
- A `litestream.yml` of its own, reading Cellar's endpoint from the
  environment instead of Tigris's (see
  [Litestream](litestream.md#on-another-host)): a host without volumes
  cannot mount it, so it goes in the image, a small `Dockerfile` copying
  it over the `fly` target's.
- At most one instance.

## To check

First how it deploys: if it starts the new instance before stopping the
old one, both would write apart, and a lock in S3 would be needed (see
[Litestream](litestream.md#without-a-persistent-disk)).
