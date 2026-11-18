# Deployment on Railway

> **Not tried yet.** What we know of Railway, before trying it;
> nothing here was deployed. Still to do: see the
> [to do](../../TODO.md#hosts-to-try-and-document).

What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

[Railway](https://railway.com) runs a container from a Dockerfile or an
image, with volumes, in a European region, billed by use: the closest to
[Render](render.md).

## What we expect

- Build the `final` target of the `Dockerfile`, or pull the `sqlite` image
  from ghcr.io (`.github/workflows/sqlite-image.yml`).
- A volume on `/data`, with `DATABASE_PATH=/data/padocs.db`. Railway mounts
  it as root: the image starts as root, gives the database's folder to
  `nobody` and runs as `nobody` (`bin/start`), as on Render.
- One replica, so that one instance writes.
- `PHX_HOST` set to the domain Railway gives, or to your own.
- The health check on `/health`.

## To check

How it deploys with a volume (stopping the old instance first, as Render
does, or not), and what a volume and the memory cost.
