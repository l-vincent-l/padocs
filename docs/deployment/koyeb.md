# Deployment on Koyeb

> **Not tried yet.** What we know of Koyeb, before trying it;
> nothing here was deployed. Still to do: see the
> [to do](../../TODO.md#hosts-to-try-and-document).

What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

[Koyeb](https://www.koyeb.com) runs containers in Paris and Frankfurt, and
can put them to sleep while nobody is connected.

## What we expect

- The `final` target, or the `sqlite` image from ghcr.io.
- A volume on `/data` for the SQLite file and the images, one instance.

## To check

Its volumes are recent and limited: check first what they allow (size,
regions, one instance attached), how it deploys with one, and how waking up
from sleep goes with a WebSocket application.
