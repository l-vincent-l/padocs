# Local setup

How to run Padocs on your machine, to try it or to work on it.

## Prerequisites

| Tool | Version | Why |
|---|---|---|
| Erlang/OTP and Elixir | Elixir 1.17 or later (the Docker image uses Elixir 1.20.4 on OTP 29) | the application |
| Rust | 1.91 or later, from [rustup](https://rustup.rs) | the search index ([Tantivy](https://github.com/quickwit-oss/tantivy)) is compiled from source |
| Node.js and npm | a current LTS | the editor's JavaScript dependencies (BlockNote, Yjs) |
| A C compiler | `build-essential` on Debian and Ubuntu, Xcode's command line tools on macOS | SQLite and other native dependencies |

Nothing else: the database is a SQLite file, created in the repository.

With Docker, none of these are needed: [develop in a container](#develop-in-docker),
or [try the production image](#try-the-production-image).

## First run

```sh
git clone <this repository> padocs
cd padocs

# The editor's dependencies, read by esbuild
npm ci --prefix assets

# Elixir dependencies, the database (base.sqlite), esbuild and Tailwind
mix setup

# The server, with live reload
iex -S mix phx.server
```

The first `mix setup` takes a few minutes: it compiles the Rust part of the
search index. Typst, which makes the PDFs, comes precompiled.

Open [localhost:4000](http://localhost:4000) and create an account with an
email address and a password.

## Develop in Docker

`compose.yaml` runs the development server in a container (`Dockerfile.dev`,
with Elixir, Rust and Node), on the repository mounted at `/app`: edit the
code on your machine, the page reloads as usual.

```sh
HOST_UID=$(id -u) HOST_GID=$(id -g) docker compose up --build
```

`HOST_UID` and `HOST_GID` make the container run as you, so that the files it
writes in the repository (`base.sqlite`, `files/`) stay yours. The first start
takes several minutes: it installs the dependencies and compiles them, Rust
included. They are kept in volumes (`deps`, `_build`,
`assets/node_modules`), apart from those of your machine, whose native code
would not run in the container: the next starts are quick.

Then open [localhost:4000](http://localhost:4000); emails are at
[localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox) as below.

```sh
docker compose attach dev           # the IEx shell (Ctrl+P Ctrl+Q to leave it)
docker compose exec dev mix test    # the tests, while the server runs
docker compose exec dev mix precommit
docker compose down                 # stop; `down -v` also drops the volumes
```

On macOS and Windows, file changes in a mounted folder reach the container
more slowly than on Linux: the reload may take a second or two.

## Try the production image

The production image runs locally too, with only Docker installed. It is
built from the repository; the first build takes several minutes (it compiles
the search index's Rust code).

```sh
docker build --target final -t padocs .

# A volume for the database and the images, handed to the image's user
# (nobody, uid 65534)
docker volume create padocs-data
docker run --rm -v padocs-data:/data debian:trixie-slim chown 65534:65534 /data

docker run --rm -it --name padocs \
  -p 4000:4000 \
  -v padocs-data:/data \
  -e SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  -e PHX_HOST=localhost \
  -e DATABASE_PATH=/data/padocs.db \
  padocs
```

Then open [localhost:4000](http://localhost:4000). It is the production
build, so some things differ from `mix phx.server`:

- **No live reload**: a change to the code takes a new `docker build`.
- **Emails are written to the container's output**, not to a mailbox (see
  [Emails](deployment.md#emails)). Their links start with `https://localhost/`,
  the address the application believes it has: open them as
  `http://localhost:4000/...` instead.
- **A new `SECRET_KEY_BASE` at each start signs everyone out.** To stay
  signed in across restarts, generate it once and pass the same value.

The data stays in the `padocs-data` volume; `docker volume rm padocs-data`
starts over. To deploy this image for real, see [Deployment](deployment.md).

## Emails

While developing, emails are not sent: they are kept in memory and shown at
[localhost:4000/dev/mailbox](http://localhost:4000/dev/mailbox). The links to
confirm an address, sign in by email or reset a password are there. They are
lost when the server restarts.

## The dashboard

The Phoenix LiveDashboard is at
[localhost:4000/admin/dashboard](http://localhost:4000/admin/dashboard),
without a password while developing: processes, memory, and on the Metrics
page the time of the database queries.

## Tests and checks

```sh
mix test             # the tests, against base_tests.sqlite
mix test --failed    # only those that failed last time
mix precommit        # what to run before a commit: warnings as errors,
                     # formatting, translations up to date, tests
```

The interface is written in English in the code and translated in
`priv/gettext/fr`. After adding or changing a text:

```sh
mix gettext.extract --merge
```

then fill in the new French translations in
`priv/gettext/fr/LC_MESSAGES/default.po`.

## Sign in with GitHub or GitLab (optional)

Create an OAuth application on GitHub (Settings > Developer settings > OAuth
Apps) or GitLab (Preferences > Applications, scopes `openid`, `email` and `profile`),
with the callback URL:

- `http://localhost:4000/auth/user/github/callback`
- `http://localhost:4000/auth/user/gitlab/callback`

Then start the server with its credentials:

```sh
export GITHUB_CLIENT_ID=... GITHUB_CLIENT_SECRET=...
export GITLAB_CLIENT_ID=... GITLAB_CLIENT_SECRET=...
# GITLAB_URL=https://gitlab.example.org for a self-hosted GitLab
iex -S mix phx.server
```

Without them, the sign-in page still shows the buttons, but signing in with
the provider fails.

## A libSQL database instead of SQLite (optional)

The database adapter is chosen at compile time. To run against a libSQL
server, such as Bunny Database or a local `sqld`:

```sh
export DATABASE_ADAPTER=hrana BUNNY_DATABASE_URL=http://127.0.0.1:8080
mix compile --force   # the adapter is compiled in
mix phx.server
```

## Starting over

```sh
mix ecto.reset    # drops base.sqlite and creates it again
rm -rf files/     # the images of the documents, stored next to the database
```
