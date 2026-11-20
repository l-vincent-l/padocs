# Deployment on Render

[Render](https://render.com) builds the image from the repository and runs it
behind its HTTPS, with a persistent disk for the SQLite database. What Padocs
needs, the emails and the storage of the images: [Deployment](README.md);
every variable: [Configuration](../configuration.md).

`render.yaml` describes the service (a Blueprint). Tried on Render, from the
repository.

## Create the service

1. **New** → **Blueprint**, then the repository (a fork of yours, or
   `https://github.com/l-vincent-l/padocs`) and its branch. **Blueprint
   Path**: `render.yaml`, the default.
2. Render reads `render.yaml` and asks for `SECRET_KEY_BASE`: at least 64
   characters, from `mix phx.gen.secret` or `openssl rand -base64 48`. Keep
   it: a new one signs everyone out.
3. **Apply**. The first build compiles the Elixir dependencies: a few
   minutes.

Padocs is then at `https://padocs.onrender.com`, or the name Render gave the
service: without `PHX_HOST`, the host name is the one Render sets in
`RENDER_EXTERNAL_HOSTNAME`. For a domain of your own, add it in the service's
**Settings** → **Custom Domains**, and set `PHX_HOST` to it.

## What `render.yaml` sets

| | |
|---|---|
| Instance | `0.5c-512mb`, the smallest paid one: a disk needs a paid instance |
| Region | `frankfurt` |
| Disk | `padocs-data`, 1 GB, mounted on `/data`; it can grow, not shrink |
| Variables | `DATABASE_PATH=/data/padocs.db`, `SECRET_KEY_BASE` asked at creation |
| Health check | `/health`, 200 once the database answers |

Render builds the last stage of the `Dockerfile`, `final`: it cannot choose
another. Its disk is mounted as root; the image starts as root, gives the
database's folder to `nobody`, then runs as `nobody` (`bin/start`).

The other variables (GitHub sign-in, images on S3, the dashboard…) go in the
service's **Environment**: `sync: false` variables of `render.yaml` are only
asked when the Blueprint is created.

## What a disk implies

- **One instance**: a service with a disk cannot be scaled, which SQLite
  needs anyway.
- **A short interruption on each deploy**: Render stops the old instance
  before starting the new one, so that only one writes to the database.
- **Backups**: Render snapshots the disk every 24 hours and keeps the
  snapshots 7 days, restored whole from the dashboard. A snapshot taken
  while the database is written may not hold its last transactions, and
  Render advises against them for databases: for a continuous backup, see
  [Litestream](litestream.md).
