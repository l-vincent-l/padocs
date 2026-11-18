# Deployment on Scaleway Serverless Containers

> **Not tried yet.** What we know of Scaleway Serverless Containers, before
> trying it; nothing here was deployed. Still to do: see the
> [to do](../../TODO.md#hosts-to-try-and-document).

What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

[Scaleway Serverless
Containers](https://www.scaleway.com/en/serverless-containers/) (French) run
a container, put to sleep while nobody is connected, without any volume.
Scaleway's Object Storage gives the S3.

## What we expect

- The `fly` target of the `Dockerfile`, with Litestream: it restores the
  database from the Object Storage when the disk is empty, then streams
  every write to it (see
  [Litestream](litestream.md#without-a-persistent-disk), and its
  conditions).
- The images in the Object Storage too (`FILES_S3_BUCKET`).
- A `litestream.yml` of its own, reading the Object Storage's endpoint from the
  environment instead of Tigris's (see
  [Litestream](litestream.md#on-another-host)): a host without volumes
  cannot mount it, so it goes in the image, a small `Dockerfile` copying
  it over the `fly` target's.
- At most one instance (minimum and maximum 1, or 0 to sleep).
- Waking up restores the database: a few more seconds on the first request.

## To check

How it deploys: overlapping instances would need a lock in S3. If libSQL
is preferred, Bunny Database (see [Bunny](bunny.md)) rather than a second
container running libSQL: that one would have no disk either, so would be
restored at start too, could never sleep, and each query would go over the
network.
