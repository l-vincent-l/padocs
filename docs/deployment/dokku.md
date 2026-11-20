# Deployment on Dokku

[Dokku](https://dokku.com) turns a server of yours into a small Heroku: you
deploy with `git push`, it builds the image from the `Dockerfile` and runs it
behind nginx. What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

Tried with Dokku 0.38 on Ubuntu 24.04, except for Let's Encrypt, which
needs a public domain.

## The server

Install Dokku on the server by its
[script](https://dokku.com/docs/getting-started/installation/), then give it
your SSH key, the one `git push` will use:

```sh
cat ~/.ssh/id_ed25519.pub | ssh root@server dokku ssh-keys:add admin
```

The image is built on the server, its Elixir dependencies compiled there;
the native libraries (the search index, Yjs, Typst) are downloaded
precompiled. Without Docker's cache, the build took 2 minutes on 8 CPUs; the
next ones reuse the cache (16 s here).

## Create the application

On the server (`dokku` as root, or `ssh dokku@server <command>`):

```sh
dokku apps:create padocs
dokku git:set padocs deploy-branch main
dokku domains:set padocs docs.example.org
dokku ports:set padocs http:80:4000
dokku storage:mount padocs padocs-data:/data
dokku checks:set padocs wait-to-retire 10
dokku config:set --no-restart padocs \
  SECRET_KEY_BASE="$(openssl rand -base64 48)" \
  PHX_HOST=docs.example.org \
  DATABASE_PATH=/data/padocs.db
```

- `ports:set`: without it, Dokku serves the port of the image's `EXPOSE`,
  4000, instead of 80.
- `storage:mount`: the Docker volume `padocs-data`, on `/data`, holds the
  database and the images. The image gives it to `nobody`, which the
  release runs as.
- `wait-to-retire`: on each deploy, the old container keeps running 60 s by
  default once the new one serves; during that time, two people on the same
  document may be on two containers and not see each other's edits. 10 s is
  enough for the old one to finish its requests.
- `config:set` prints the values, `SECRET_KEY_BASE` included: keep it, a new
  one signs everyone out.

The other variables (GitHub sign-in, images on S3, the dashboard…) are set
the same way, with `config:set`.

## Deploy

From your clone of the repository:

```sh
git remote add dokku dokku@server:padocs
git push dokku main
```

Dokku reads `app.json` from the repository: before sending traffic to a new
container, it waits until `/health` answers (200 once the database does).

## HTTPS

With the [Let's Encrypt plugin](https://github.com/dokku/dokku-letsencrypt),
on the server, once the domain points to it:

```sh
dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
dokku letsencrypt:set padocs email you@example.org
dokku letsencrypt:enable padocs
dokku letsencrypt:cron-job --add
```

Padocs redirects HTTP to HTTPS: until the certificate is there, its pages
answer with a redirection (only `/health` answers over HTTP).

## Day to day

```sh
dokku logs padocs -t                          # the logs, and the emails while no provider is configured
dokku enter padocs web bin/padocs remote      # an IEx console in the running release
dokku ps:rebuild padocs                       # build and deploy the current version again
```

## Backups

The database and the images are in the Docker volume `padocs-data`
(`docker volume inspect padocs-data` shows where). Copy it while the
application is stopped (`dokku ps:stop padocs`, then `dokku ps:start
padocs`), or stream the database to S3 with [Litestream](litestream.md);
not tried with Dokku yet.
