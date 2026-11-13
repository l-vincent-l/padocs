# Deployment

Padocs is one Elixir release. It needs:

- a place for its **database**: a SQLite file on a persistent disk, or a remote
  libSQL database (Bunny Database);
- a place for the **images** of the documents: a folder on the same disk, an
  S3 bucket or a Bunny Storage zone;
- **HTTPS** in front of it, from your host or a reverse proxy: the
  application builds its links as `https://<PHX_HOST>`.

A small machine is enough: the reference deployment runs on one shared CPU and
512 MB of memory (see [the load tests](performance.md) for what it
holds).

## Environment variables

| Variable | Required | Meaning |
|---|---|---|
| `SECRET_KEY_BASE` | yes | signs and encrypts the cookies; generate one with `mix phx.gen.secret` and keep it |
| `PHX_HOST` | yes | the public host name, e.g. `docs.example.org` |
| `DATABASE_PATH` | with SQLite | the database file, on a persistent disk, e.g. `/data/padocs.db` |
| `PORT` | no | the HTTP port, `4000` by default |
| `POOL_SIZE` | no | database connections, `3` for SQLite, `10` for libSQL |
| `FILES_PATH` | no | the folder of the images, by default `files/` next to the database |
| `DASHBOARD_USER`, `DASHBOARD_PASSWORD` | no | turn on the LiveDashboard at `/admin/dashboard`, behind HTTP basic auth |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | no | sign-in with GitHub; callback `https://<PHX_HOST>/auth/user/github/callback` |
| `GITLAB_CLIENT_ID`, `GITLAB_CLIENT_SECRET`, `GITLAB_URL` | no | sign-in with GitLab (gitlab.com by default); callback `https://<PHX_HOST>/auth/user/gitlab/callback` |

A self-hosted GitLab must be one trusted to verify its users' email addresses:
whoever runs it could otherwise sign in to any account with the same address.

The variables of the image storage and of libSQL are in their own sections
below.

## Emails

Padocs sends emails to confirm an address, to sign in by a link and to reset
a password. An account registered with a password must confirm its address
within 7 days, or its password stops signing in until it is reset.

**No email provider is configured yet:** in production the emails are written
to the logs, links included (`config/prod.exs`). That is enough to try
Padocs, reading the links in the logs; for real users, set a
[Swoosh adapter](https://hexdocs.pm/swoosh/Swoosh.html#module-adapters) in
`config/runtime.exs`, for instance:

```elixir
config :padocs, Padocs.Mailer,
  adapter: Swoosh.Adapters.Brevo,
  api_key: System.get_env("BREVO_API_KEY")
```

The API adapters use Req, already configured as Swoosh's HTTP client in
production. Then remove the `Swoosh.Adapters.Logger` lines from
`config/prod.exs`.

## With Docker

The `Dockerfile` builds the release. Its `final` target runs the migrations,
then the server, as the `nobody` user:

```sh
docker build --target final -t padocs .
```

The database and the images go on a volume. The image runs as `nobody` (uid
65534): give it the volume first.

```sh
docker volume create padocs-data
docker run --rm -v padocs-data:/data debian:trixie-slim chown 65534:65534 /data

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
stopped, or run [Litestream](https://litestream.io) next to it to stream the
database to S3 continuously, as the Fly.io image does (see below).

## On Fly.io, with Litestream

The `fly` target of the `Dockerfile` adds Litestream: the SQLite file lives on
a Fly volume and is streamed to a Tigris bucket. On a new machine, it is
restored from the bucket before the start (`rel/overlays/bin/fly_start`).
The machine is suspended when no one is connected and resumed on the next
request.

`fly.toml` is the configuration of the reference deployment. For your own,
change `app`, `PHX_HOST` and the volume's name, then:

```sh
fly apps create <app>
fly volumes create <volume> --size 1 --region cdg
fly storage create                 # a Tigris bucket: sets BUCKET_NAME and the AWS_* secrets
fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)"
fly deploy
```

Litestream's bucket can also hold the images: set `FILES_S3_BUCKET` to its
name and `FILES_S3_PREFIX=files-store/`, for instance.

The reference deployment kept its former names: the app `textexp`, the volume
`textexp_data`, the file `/data/textexp.db` and its path in the bucket
(`litestream.yml`). Change them together for a new deployment.

## On Bunny

The image of the `final` target built with `DATABASE_ADAPTER=hrana` uses a
remote libSQL database, Bunny Database, instead of a SQLite file. The GitHub
workflow `.github/workflows/bunny-image.yml` builds it and pushes it to
ghcr.io (Actions > Bunny image > Run workflow); it is then deployed by hand on
a Bunny Magic Container.

The container reads:

| Variable | Meaning |
|---|---|
| `BUNNY_DATABASE_URL` | the libSQL URL of the database |
| `BUNNY_DATABASE_AUTH_TOKEN` | its token |

The database being remote, the images need a storage zone or a persistent
volume (see below): without either, they go to a temporary folder, lost when
the container restarts.

## Storage of the images

The images of the documents, pasted or dropped in the editor or found in an
imported Word file, are stored by `Padocs.Files`: PNG, JPEG, GIF or WebP,
10 MB each at most. They are served at `/files/<id>` to whoever can read
their document (anyone while it has a public link), and deleted with it, for
good.

| Storage | Set by |
|---|---|
| S3 bucket (Tigris, AWS, MinIO…), private: a browser is redirected to a URL signed for 5 minutes | `FILES_S3_BUCKET`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION` (`auto` by default), `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optionally `FILES_S3_PREFIX` |
| Bunny Storage zone, private: the application reads and sends the bytes | `STORAGE_ZONE`, `STORAGE_ACCESS_KEY`, `STORAGE_REGION` or `STORAGE_HOSTNAME`, the names Bunny gives a container linked to a zone |
| Local folder, otherwise | `FILES_PATH`, by default `files/` next to the SQLite database |

## Comparing deployments

The reference instance runs twice, on Fly.io and on Bunny, to compare them:

| | Fly.io | Bunny |
|---|---|---|
| Application | one machine, suspended when idle (`fly.toml`) | Magic Container |
| Database | SQLite file on a volume | Bunny Database, through `ecto_hrana` |
| Backup | Litestream, to Tigris | Bunny's |
| Image | `fly` target, built by Fly | `final` target with `DATABASE_ADAPTER=hrana`, on ghcr.io |
| Deploy | `fly deploy` | Actions > Bunny image > Run workflow, then deploy the image on Bunny |

Each `/admin/dashboard` shows the query times measured by the server (page
Metrics, `padocs.sqlite_repo.query`), once `DASHBOARD_USER` and
`DASHBOARD_PASSWORD` are set. `scripts/compare-hosts` measures both from
outside.
