# Deployment on Bunny

The second reference deployment, compared with Fly.io. What Padocs needs, the
emails and the storage of the images: [Deployment](README.md); every variable:
[Configuration](../configuration.md).

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
volume (see [Storage of the images](README.md#storage-of-the-images)):
without either, they go to a temporary folder, lost when the container
restarts.
