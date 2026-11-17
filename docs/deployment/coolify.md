# Deployment on Coolify

[Coolify](https://coolify.io) deploys applications on your own server, with
its proxy (Traefik) and HTTPS by Let's Encrypt. What Padocs needs, the emails
and the storage of the images: [Deployment](README.md); every variable:
[Configuration](../configuration.md).

Tried with Coolify 4 on Ubuntu 24.04.

## The server

Coolify runs on a server of yours (a VPS), installed by its script or
managed from Coolify Cloud. Padocs is built on that server: give it 2 GB of
memory at least, with Coolify on the same machine, and point the domain of
Padocs (an `A` record) to it.

## Create the resource

The repository holds `docker-compose.coolify.yaml`, which Coolify reads for
the domain, the port, the secret key and the volume:

1. In a project, **+ New** → **Public Repository**:
   `https://github.com/l-vincent-l/padocs`. For a branch other than the
   default one, put it in the URL:
   `https://github.com/l-vincent-l/padocs/tree/<branch>`.
2. **Build Pack**: **Docker Compose**.
3. **Docker Compose Location**: `/docker-compose.coolify.yaml`.
4. **Continue**.
5. On the `padocs` service, set **Domains** to `https://docs.example.org`
   (with `https://`: Coolify proposes an `http://` sslip.io one, and Padocs
   redirects to HTTPS). **Save**.
6. **Deploy**.

From the file, Coolify:

- generates `SECRET_KEY_BASE`, once, and keeps it across deployments
  (`SERVICE_BASE64_64_PHOENIX`);
- routes the domain to port 4000 (`SERVICE_URL_PADOCS_4000`) and gives its
  host name to `PHX_HOST` (`SERVICE_FQDN_PADOCS`): changing the domain changes
  `PHX_HOST` at the next deployment;
- creates the volume `padocs-data`, mounted on `/data`, where the database
  is (`DATABASE_PATH=/data/padocs.db`) and the images by default. The image
  gives it to `nobody`, which the release runs as;
- gives a stop 30 s, for the documents being edited to save their last
  edits.

The other variables (GitHub sign-in, images on S3, the dashboard…) go in the
resource's **Environment Variables**.

## Building on the server, or not

With `docker-compose.coolify.yaml`, Coolify builds the image on the server:
the Elixir dependencies and the Rust code of the search index and of Yjs.
On 2 virtual CPUs, the first build took about a quarter of an hour; the
next ones reuse Docker's cache and are much faster, as long as the
dependencies do not change.

To skip the build, pull the image that GitHub builds on every push to main
(`.github/workflows/sqlite-image.yml`) instead. No repository is needed then:
**+ New** → **Docker Compose Empty**, and paste `docker-compose.coolify.yaml`
with its `build:` block replaced by

```yaml
    image: ghcr.io/l-vincent-l/padocs:sqlite
```

A deployment then only pulls the image: to update, deploy again. A fork
publishes its own, `ghcr.io/<owner>/<repository>:sqlite`; its package must be
public on GitHub for Coolify to pull it without credentials. The image is
built for `linux/amd64` only. This way has not been tried yet: the image is
published once this workflow has run on main.

## Backups

The volume holds everything. Coolify backs up the databases it manages
itself, not a SQLite file in a volume: copy the volume while the
application is stopped, or stream the database to S3 with
[Litestream](litestream.md). For the latter, build the `fly` target instead
of `final` (`target: fly` in a copy of the compose file) and add the
variables of Litestream; not tried on Coolify yet.
