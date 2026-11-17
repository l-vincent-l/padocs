# Deployment with Docker

On any machine with Docker. What Padocs needs, the emails and the storage of
the images: [Deployment](README.md); every variable:
[Configuration](../configuration.md).

The `Dockerfile` builds the release. Its `final` target runs the migrations,
then the server, as the `nobody` user:

```sh
docker build --target final -t padocs .
```

The database and the images go on a volume. The image starts as root, gives
the database's folder to `nobody` (uid 65534), then runs as `nobody`: a named
volume or a folder of the host (`-v /srv/padocs:/data`) needs no `chown`
first.

```sh
docker run -d --name padocs --restart unless-stopped \
  -p 4000:4000 \
  -v padocs-data:/data \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=docs.example.org \
  -e DATABASE_PATH=/data/padocs.db \
  padocs
```

Generate `SECRET_KEY_BASE` once and keep it, in a `.env` file for instance:
a new one signs everyone out.

Put a reverse proxy with HTTPS in front of port 4000 (Caddy, nginx,
Traefik…). It must pass the WebSocket upgrade through: the editor and the
pages talk to the server over WebSockets. With Caddy:

```
docs.example.org {
  reverse_proxy localhost:4000
}
```

**Backups.** The volume holds everything. Copy it while the application is
stopped, or run [Litestream](litestream.md) next to it to stream the
database to S3 continuously, as the [Fly.io image](fly-io.md) does.
