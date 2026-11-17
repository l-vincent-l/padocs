# Deployment on Fly.io, with Litestream

The reference deployment. What Padocs needs, the emails and the storage of the
images: [Deployment](README.md); every variable:
[Configuration](../configuration.md).

The `fly` target of the `Dockerfile` adds Litestream: the SQLite file lives on
a Fly volume and is streamed to a Tigris bucket. On a new machine, it is
restored from the bucket before the start (`rel/overlays/bin/fly_start`).
The machine is suspended when no one is connected and resumed on the next
request.

`fly.toml` is a template for your own deployment. Set its `app`, a name of
your own, unique on Fly.io, then:

```sh
fly apps create <app>
fly volumes create padocs_data --size 1 --region cdg
fly storage create                 # a Tigris bucket: sets BUCKET_NAME and the AWS_* secrets
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly deploy
```

The application is then at `https://<app>.fly.dev`: without `PHX_HOST`, the
host name comes from the app's name (`FLY_APP_NAME`, set by Fly). For a
domain of your own, set `PHX_HOST` in `[env]` and add its certificate
(`fly certs add docs.example.org`).

The volume's name, `padocs_data`, and the database file, `/data/padocs.db`,
can be changed in `fly.toml`; the replica in the bucket is `padocs.db` (see
[Litestream](litestream.md)).

Litestream's bucket can also hold the images: set `FILES_S3_BUCKET` to its
name and `FILES_S3_PREFIX=files-store/`, for instance.

## The reference deployment

[textexp.fly.dev](https://textexp.fly.dev) kept the names it had before
Padocs was renamed: the app `textexp`, the volume `textexp_data`, the file
`/data/textexp.db` and the replica `textexp.db` in the bucket. Its
configuration is `fly.textexp.toml`:

```sh
fly deploy -c fly.textexp.toml
```
