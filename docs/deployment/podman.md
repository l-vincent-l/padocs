# Deployment with Podman

On any Linux machine with [Podman](https://podman.io) 4.4 or later, rootless,
started by systemd. What Padocs needs, the emails and the storage of the
images: [Deployment](README.md); every variable:
[Configuration](../configuration.md).

This guide follows the [Docker one](docker.md), whose image it builds. Tried
with Podman 5.7, rootless.

## Build the image

The `final` target of the `Dockerfile` runs the migrations, then the server,
as the `nobody` user:

```sh
podman build --target final -t padocs .
```

The image is then `localhost/padocs:latest`.

## The volume and the secret

The database and the images go on a volume. The image runs as `nobody` (uid
65534 in the container), and its `/data` belongs to it: a new named volume
mounted there takes that owner, nothing to `chown`.

```sh
podman volume create padocs-data
```

Keep `SECRET_KEY_BASE` in a Podman secret rather than in a file: generate it
once, a new one signs everyone out.

```sh
openssl rand -base64 48 | podman secret create padocs_secret_key_base -
```

(`mix phx.gen.secret` gives an equivalent one.)

## Try it

```sh
podman run -d --name padocs \
  -p 127.0.0.1:4000:4000 \
  -v padocs-data:/data \
  --secret padocs_secret_key_base,type=env,target=SECRET_KEY_BASE \
  -e PHX_HOST=docs.example.org \
  -e DATABASE_PATH=/data/padocs.db \
  --stop-timeout 30 \
  localhost/padocs
```

`--stop-timeout 30` leaves the documents being edited time to save their last
edits on stop (Podman's default is 10 s). `podman logs -f padocs` shows the
logs, and the emails while no provider is configured.

Stop and remove it before going on: `podman rm -f padocs`.

## Run it with systemd (Quadlet)

`--restart` does not bring a rootless container back after a reboot; a
[Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
file makes it a systemd service. Write
`~/.config/containers/systemd/padocs.container`:

```ini
[Unit]
Description=Padocs

[Container]
Image=localhost/padocs:latest
ContainerName=padocs
PublishPort=127.0.0.1:4000:4000
Volume=padocs-data:/data
Secret=padocs_secret_key_base,type=env,target=SECRET_KEY_BASE
Environment=PHX_HOST=docs.example.org
Environment=DATABASE_PATH=/data/padocs.db
StopTimeout=30

[Service]
Restart=always
TimeoutStopSec=40

[Install]
WantedBy=default.target
```

Other variables (images on S3, GitHub sign-in…) go on more `Environment=`
lines, or as secrets the same way. Then:

```sh
systemctl --user daemon-reload
systemctl --user start padocs
journalctl --user -u padocs -f       # the logs
loginctl enable-linger "$USER"       # start it at boot, without a session
```

To deploy a new version: build the image again, then
`systemctl --user restart padocs`.

## HTTPS

Put a reverse proxy with HTTPS in front of port 4000 (Caddy, nginx,
Traefik…). It must pass the WebSocket upgrade through: the editor and the
pages talk to the server over WebSockets. With Caddy:

```
docs.example.org {
  reverse_proxy localhost:4000
}
```

## Backups

The volume holds everything; `podman volume inspect padocs-data` shows where
it is on the disk. Copy it, or
`podman volume export padocs-data > padocs-data.tar`, while the service is
stopped: a copy of a database being written may not open. To stream the database
to S3 continuously, run [Litestream](litestream.md) next to it, as the
[Fly.io image](fly-io.md) does.
