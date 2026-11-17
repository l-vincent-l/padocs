# Configuration

Padocs is configured by environment variables, read at start by
`config/runtime.exs`, except `DATABASE_ADAPTER`, read when compiling. How to
deploy it: [Deployment](deployment/README.md).

## Minimal production setup

With a SQLite file and the images next to it, three variables are enough:

```sh
SECRET_KEY_BASE="$(mix phx.gen.secret)"
PHX_HOST=docs.example.org
DATABASE_PATH=/data/padocs.db
```

The release started by `bin/server` (as the Docker image does, through
`bin/start`) sets `PHX_SERVER=true` itself.

## Application

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `SECRET_KEY_BASE` | yes, in production | | signs and encrypts the cookies; generate one with `mix phx.gen.secret` and keep it: a new one signs everyone out |
| `PHX_HOST` | yes, in production, but on Fly.io and Render | `<app>.fly.dev` on Fly.io (from `FLY_APP_NAME`), the `RENDER_EXTERNAL_HOSTNAME` on Render, else `example.com` | the public host name; the links are built as `https://<PHX_HOST>` |
| `PORT` | no | `4000` | the HTTP port |
| `PHX_SERVER` | for a release | | starts the HTTP server; set by `bin/server` |
| `DNS_CLUSTER_QUERY` | no | | a DNS name whose records are the other nodes to connect to (`DNSCluster`); without it, one node |
| `PHX_LISTEN_ALL` | no, development only | | listens on every interface instead of `127.0.0.1`, e.g. in a container |

## Database

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `DATABASE_ADAPTER` | no | `sqlite3` | `hrana` for a libSQL server (Bunny Database) instead of a SQLite file. Read **at compile time**: in Docker, a build argument (`--build-arg DATABASE_ADAPTER=hrana`); locally, `mix compile --force` after changing it |
| `DATABASE_PATH` | with SQLite, in production | | the database file, on a persistent disk, e.g. `/data/padocs.db` |
| `BUNNY_DATABASE_URL` | with `hrana` | | the libSQL URL of the database |
| `BUNNY_DATABASE_AUTH_TOKEN` | no | | its token |
| `POOL_SIZE` | no | `3` for SQLite, `10` for libSQL | database connections. SQLite writes one transaction at a time: more connections only wait longer |

## Storage of the images

The first storage whose variable is set is used: an S3 bucket, then a Bunny
Storage zone, then a local folder.

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `FILES_S3_BUCKET` | for S3 | | the bucket (Tigris, AWS, MinIO…) |
| `FILES_S3_PREFIX` | no | empty | a prefix for the keys, e.g. `files-store/` to share Litestream's bucket |
| `AWS_ENDPOINT_URL_S3` | with S3 | | the S3 endpoint, e.g. `https://fly.storage.tigris.dev` |
| `AWS_REGION` | no | `auto` | the region |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | with S3 | | the credentials |
| `STORAGE_ZONE` | for Bunny Storage | | the zone; Bunny sets these variables in a container linked to it |
| `STORAGE_ACCESS_KEY` | with Bunny Storage | | the zone's password |
| `STORAGE_REGION` or `STORAGE_HOSTNAME` | no | | where the zone is |
| `FILES_PATH` | no | `files/` next to `DATABASE_PATH` | the local folder of the images. Without it nor `DATABASE_PATH`, a temporary folder, lost when the container restarts |

`fly storage create` sets `AWS_ENDPOINT_URL_S3`, `AWS_REGION`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `BUCKET_NAME`.

## Sign-in with GitHub or GitLab

Each needs an OAuth application on the provider, whose callback URL is
`https://<PHX_HOST>/auth/user/github/callback` (resp. `.../gitlab/callback`),
`http://localhost:<PORT>/auth/...` in development. Without its client id and
secret, signing in with that provider fails; password and email-link sign-in
still work.

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | for GitHub | | the OAuth application on GitHub |
| `GITLAB_CLIENT_ID`, `GITLAB_CLIENT_SECRET` | for GitLab | | the OAuth application on GitLab |
| `GITLAB_URL` | no | `https://gitlab.com` | a self-hosted GitLab |

A self-hosted GitLab must be one trusted to verify its users' email addresses
as gitlab.com does: whoever runs it could otherwise sign in to any account
with the same address.

## Administration

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `DASHBOARD_USER`, `DASHBOARD_PASSWORD` | no | | turn on the LiveDashboard at `/admin/dashboard`, behind HTTP basic auth; without them, it is not served |

## Fly.io and Litestream

Read by `litestream.yml` and `bin/fly_start` in the image of the `fly`
target.

| Variable | Required | Meaning |
|---|---|---|
| `DATABASE_PATH` | yes | the database file on the volume, streamed by Litestream |
| `BUCKET_NAME` | yes | the bucket of the replica, set by `fly storage create` |
| `LITESTREAM_REPLICA_PATH` | no | the replica's path in the bucket, `padocs.db` by default (set in the image) |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | yes | its credentials, set by `fly storage create` |

## Emails

No email provider is read from the environment yet: in production the emails
are written to the logs. See [Deployment, Emails](deployment/README.md#emails) to
configure one.
