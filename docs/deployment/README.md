# Deployment

Padocs is one Elixir release. It needs:

- a place for its **database**: a SQLite file on a persistent disk, or a remote
  libSQL database (Bunny Database);
- a place for the **images** of the documents: a folder on the same disk, an
  S3 bucket or a Bunny Storage zone;
- **HTTPS** in front of it, from your host or a reverse proxy: the
  application builds its links as `https://<PHX_HOST>`.

A small machine is enough: the reference deployment runs on one shared CPU and
512 MB of memory (see [the load tests](../performance.md) for what it
holds).

## Configuration

At least `SECRET_KEY_BASE`, `PHX_HOST` and, with SQLite, `DATABASE_PATH`.
Every variable, with its default: [Configuration](../configuration.md).

## Hosts

- [Docker](docker.md): on any machine, behind a reverse proxy with HTTPS.
- [Podman](podman.md): the same image, rootless, as a systemd service
  (Quadlet).
- [Coolify](coolify.md): on a server of yours, from
  `docker-compose.coolify.yaml`, with HTTPS by Let's Encrypt.
- [Kamal](kamal.md): from your computer to a server of yours, over SSH,
  with HTTPS by Let's Encrypt.
- [Dokku](dokku.md): a small Heroku on a server of yours, deployed by
  `git push`.
- [Render](render.md): from `render.yaml`, with a persistent disk.
- [Fly.io](fly-io.md): one machine suspended when idle, SQLite on a volume
  streamed to Tigris by Litestream. The reference deployment.
- [Bunny](bunny.md): a Magic Container with Bunny Database (libSQL).

And for the backups of a SQLite database, on any of them:
[Litestream](litestream.md).

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
