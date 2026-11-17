# Backups with Litestream

[Litestream](https://litestream.io) streams the SQLite database to an S3
bucket as it is written: the replica is about a second behind, so a lost disk
costs about a second of edits, and the database can be restored as it was at
an earlier point, as far back as the replica goes. It only applies to a SQLite file: with Bunny
Database (libSQL), the backups are Bunny's.

The Fly.io image runs it; any other host can, with the same image. The images
of the documents are not in the database: keep them in a bucket too
(`FILES_S3_BUCKET`, see [Storage of the images](README.md#storage-of-the-images)),
or back up their folder apart.

## In the Fly.io image

The `fly` target of the `Dockerfile` adds the `litestream` binary (version
0.5.17) and its configuration, `litestream.yml`:

```yaml
dbs:
  - path: ${DATABASE_PATH}
    replica:
      url: s3://${BUCKET_NAME}/${LITESTREAM_REPLICA_PATH}?endpoint=fly.storage.tigris.dev&region=auto
```

Its entry point, `rel/overlays/bin/fly_start`, starts as root, gives the
volume to `nobody`, then, as `nobody`:

1. restores the database from the bucket when the volume holds none
   (`litestream restore -if-db-not-exists -if-replica-exists`): a new machine
   or a new volume starts from the last replica, an empty bucket from an
   empty database;
2. runs the release under Litestream
   (`litestream replicate -exec "... bin/migrate && exec bin/server"`): the
   migrations, then the server, while Litestream streams the changes.

On stop, Litestream forwards the signal to the release, waits for it to exit
(the documents being edited save their last edits), then syncs one last
time: `kill_timeout = "30s"` in `fly.toml` leaves time for both.

Litestream reads the bucket and its credentials from the variables that
`fly storage create` sets: `BUCKET_NAME`, `AWS_ACCESS_KEY_ID`,
`AWS_SECRET_ACCESS_KEY` (see [Configuration](../configuration.md#flyio-and-litestream)).

The replica's path in the bucket, `LITESTREAM_REPLICA_PATH`, is `padocs.db`
by default, set in the image so that `litestream` commands run by hand find
it too. Changing it on an existing deployment starts a new replica and
leaves the old one behind; the reference deployment sets it to `textexp.db`
(`fly.textexp.toml`).

## On another host

The image of the `fly` target is not tied to Fly.io: it runs with Docker or
Podman on any machine. Only one thing in it is specific to Fly.io, the
address of the bucket in `/etc/litestream.yml`, which points to Tigris
(`fly.storage.tigris.dev`). To back up to another S3 provider, write a
`litestream.yml` of your own, which reads the endpoint and the region from
the environment:

```yaml
# litestream.yml
dbs:
  - path: ${DATABASE_PATH}
    replica:
      url: s3://${BUCKET_NAME}/${LITESTREAM_REPLICA_PATH}?endpoint=${AWS_ENDPOINT_URL_S3}&region=${AWS_REGION}
```

then build the image and start it with that file mounted in place of the
image's own (`-v ./litestream.yml:/etc/litestream.yml`):

```sh
podman build --target fly -t padocs-litestream .

podman run -d --name padocs \
  -p 127.0.0.1:4000:4000 \
  -v padocs-data:/data \
  -v ./litestream.yml:/etc/litestream.yml:ro,Z \
  --secret padocs_secret_key_base,type=env,target=SECRET_KEY_BASE \
  -e PHX_HOST=docs.example.org \
  -e DATABASE_PATH=/data/padocs.db \
  -e BUCKET_NAME=my-bucket \
  -e AWS_ENDPOINT_URL_S3=https://s3.example.com \
  -e AWS_REGION=auto \
  -e AWS_ACCESS_KEY_ID=... \
  -e AWS_SECRET_ACCESS_KEY=... \
  --stop-timeout 30 \
  padocs-litestream
```

With Docker, the same with `docker` (and without `,Z`, which only relabels
the file for SELinux). This image starts as root to give the volume to
`nobody`: the volume needs no `chown` beforehand. Rootless, Podman's root is
your own user.

## Look at the replica

From the machine (on Fly.io, `fly ssh console`), Litestream reads its
configuration:

```sh
litestream databases                 # the databases and their replica
litestream ltx "$DATABASE_PATH"      # the files of the replica, with their times
```

## Restore

To a separate file, without touching the running database, from the
machine:

```sh
litestream restore -o /tmp/restored.db "$DATABASE_PATH"
litestream restore -o /tmp/restored.db -timestamp 2026-11-17T09:00:00Z "$DATABASE_PATH"
```

or from your own computer, with the bucket's credentials in the environment
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) and the replica's URL:

```sh
litestream restore -o restored.db \
  "s3://<bucket>/padocs.db?endpoint=fly.storage.tigris.dev&region=auto"
```

`-dry-run` shows what would be restored without writing anything.

To put a restored database back in production, stop the application first:
two processes writing the same file, or a database replaced under a running
release, would corrupt it. Then, on the volume:

1. replace the database file with the restored one, owned by `nobody` (uid
   65534), which the release runs as: a file restored as root is not
   writable by it;
2. remove the `-wal` and `-shm` files next to it, and Litestream's folder,
   `.<name>-litestream` (`.padocs.db-litestream`);
3. start the application again.

Litestream sees that the database is behind its replica, and goes on from
the restored one: the next restores give the restored database plus what
was written since, not what had been written after the point restored to.

With Podman (or Docker, the same), the volume stopped:

```sh
podman stop padocs && podman rm padocs
podman run --rm -v padocs-data:/data -v .:/restore:ro,Z docker.io/debian:trixie-slim sh -c '
  cp /restore/restored.db /data/padocs.db &&
  rm -rf /data/padocs.db-wal /data/padocs.db-shm /data/.padocs.db-litestream &&
  chown 65534:65534 /data/padocs.db'
# then start it again
```

To go back to the latest replica instead, remove the database file and the
others the same way: with the `fly` image, a volume without a database is
restored from the replica at the next start.

This was tried with Podman and a local S3 (SeaweedFS): a restore to a point
in time, put back, then written to. On Fly.io, where the volume can only be
reached from a machine, it has not been tried yet.

## What it does not cover

- **The images of the documents**, unless they are in a bucket themselves.
- **Several nodes**: Litestream expects one process writing the database.
- **A deleted bucket**: the replica is the bucket. Turn on its versioning,
  or copy it elsewhere now and then.
