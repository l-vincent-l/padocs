# Deployment with Kamal

[Kamal](https://kamal-deploy.org) deploys from your computer to a server of
yours: it builds the image, sends it over SSH and starts it behind
kamal-proxy, which gets the HTTPS certificate from Let's Encrypt. What Padocs
needs, the emails and the storage of the images: [Deployment](README.md);
every variable: [Configuration](../configuration.md).

Tried with Kamal 2.12 on Ubuntu 24.04.

## What you need

- **On your computer**: Docker, Ruby and Kamal (`gem install kamal`), a clone
  of the repository.
- **A server** (a VPS) reachable over SSH, as root or as a user of the
  `docker` group, with Docker installed (Kamal installs it when it connects
  as root). 1 GB of memory is enough: the image is built on your computer.
- **A domain** whose `A` record points to the server, ports 80 and 443 open.

No Docker Hub account: `config/deploy.yml` uses the registry Kamal runs
itself (`localhost:5555`), on your computer, which the server reaches
through the SSH connection.

## Configure

In `config/deploy.yml`, replace the server's address (`192.0.2.10`) and the
host name (`docs.example.org`, twice: `proxy.host` and `PHX_HOST`). For a
user other than root, add:

```yaml
ssh:
  user: ubuntu
```

`SECRET_KEY_BASE` comes from `.kamal/secrets`, which reads it from your
environment. Generate it once and keep it, in a password manager for
instance: a new one signs everyone out.

```sh
export SECRET_KEY_BASE="$(mix phx.gen.secret)"
```

The other variables (GitHub sign-in, images on S3, the dashboard…) go in
`env.clear` of `config/deploy.yml`, or in `env.secret` and `.kamal/secrets`
for the secret ones.

## Deploy

The first time, `kamal setup` prepares the server (kamal-proxy, the volume)
and deploys:

```sh
kamal setup
```

then, for each new version:

```sh
kamal deploy
```

Kamal builds from the **committed** files only (a clean Git clone): commit
first. The first build takes a few minutes; the next ones reuse Docker's
cache.

On each deploy, Kamal starts the new container, waits until `/health`
answers (200 once the database does), switches kamal-proxy to it, then stops
the old one: no interruption. For a few seconds both run on the same SQLite
file, on the same disk, which SQLite handles; someone editing a document
during that time is moved to the new container when the old one stops, and
their editor resends what the old one had not saved.

## Day to day

```sh
kamal app logs -f                       # the logs, and the emails while no provider is configured
kamal app exec -i --reuse "bin/padocs remote"   # an IEx console in the running release
kamal rollback <version>                # back to a previous version (kamal app containers lists them)
```

`RELEASE_NODE: padocs@localhost` in `config/deploy.yml` is needed for the
console: the container's host name, given by Kamal, holds dots, which an
Erlang short node name cannot.

## Backups

The database and the images are in the Docker volume `padocs-data` of the
server (`docker volume inspect padocs-data` shows where). Copy it while the
application is stopped (`kamal app stop`, then `kamal app boot`), or stream
the database to S3 with [Litestream](litestream.md): `builder.target: fly`
and the variables of Litestream; not tried with Kamal yet.
