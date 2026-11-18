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

## One instance

Give the Magic Container **one instance, in one region**. Each instance runs
its own server for each open document, and Bunny's instances cannot reach
each other to share them, as Fly.io's machines do (`DNS_CLUSTER_QUERY`): the
people editing a document on two instances would not see each other's edits,
even by reloading the page: a document's server only reads the other
instance's edits when it starts again, once nobody has the document open on
its instance. Nothing would be lost (the database is shared, and the history
only grows), but the editing would no longer be live. The containers
of one instance share `localhost`, not the instances.
