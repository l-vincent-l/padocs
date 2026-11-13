# Textexp

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Deployment

Two deployments run the same code, to compare them. Both are started by hand.

| | Fly.io | Bunny |
|---|---|---|
| Application | one machine, suspended when idle (`fly.toml`) | Magic Container `textexp` |
| Database | SQLite file on a volume | Bunny Database, through `ecto_hrana` |
| Backup | Litestream, to Tigris | Bunny's |
| Image | `fly` target, built by Fly | `final` target with `DATABASE_ADAPTER=hrana`, on ghcr.io |
| Deploy | `fly deploy` | Actions > Bunny image > Run workflow, then deploy the image on Bunny |
| URL | https://textexp.fly.dev | https://mc-3gejc6ktt2.bunny.run |

The database is chosen at compile time by `DATABASE_ADAPTER` (`sqlite3`, the
default, or `hrana`), see `config/config.exs`. On Bunny, the container reads
`BUNNY_DATABASE_URL` and `BUNNY_DATABASE_AUTH_TOKEN`; its image is built and
pushed to ghcr.io by `.github/workflows/bunny-image.yml`.

To compare them, each `/admin/dashboard` shows the query times measured by
the server (page Metrics, `textexp.sqlite_repo.query`), once `DASHBOARD_USER`
and `DASHBOARD_PASSWORD` are set.

Locally, against a libSQL server:

    export DATABASE_ADAPTER=hrana BUNNY_DATABASE_URL=http://127.0.0.1:8080
    mix compile --force   # the adapter is compiled in
    mix phx.server

## Files

The images of the documents, pasted or dropped in the editor or found in an
imported Word file, are stored by `Textexp.Files`: PNG, JPEG, GIF or WebP,
10 MB each at most. They are served at `/files/<id>` to whoever can read
their document (anyone while it has a public link), and deleted with it, for
good.

| Storage | Set by |
|---|---|
| S3 bucket (Tigris, AWS, MinIO…), private: a browser is redirected to a URL signed for 5 minutes | `FILES_S3_BUCKET`, `AWS_ENDPOINT_URL_S3`, `AWS_REGION` (`auto` by default), `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, optionally `FILES_S3_PREFIX` |
| Local folder, otherwise | `FILES_PATH`, by default `files/` next to the SQLite database (on Fly.io, the volume) |

On Bunny, the database is remote: without a bucket, give the container a
persistent volume and set `FILES_PATH` to a folder on it (enough for a small
instance). Without either, they go to a temporary folder, lost when the
container restarts.

On Fly.io, `fly storage create` makes a Tigris bucket and sets the `AWS_*`
secrets; `FILES_S3_BUCKET` is then its name. Litestream's bucket can be
shared, with `FILES_S3_PREFIX=files-store/` for instance.

## Public link

From the share panel, the owner of a document gives it a public link,
`/p/<token>`: anyone with it reads the document live, without an account, but
not its sub-documents. A new link replaces the previous one; the link can be
removed. Its readers join `y_doc_public:<id>`, where the document's server
sends its updates but not the editors' awareness (their cursors and
addresses). See `TextexpWeb.PublicDocumentLive`.

## Export

From a document's "⋯" menu:

| Format | Made by |
|---|---|
| PDF | the server: the document as [Typst](https://typst.app) (`YexBlockNote.to_typst/2`), compiled by the `typst` package (a NIF) |
| Markdown, Typst | the server, from the saved snapshot |
| Word (.docx), OpenDocument (.odt) | the browser, from the editor, with BlockNote's `@blocknote/xl-docx-exporter` and `@blocknote/xl-odt-exporter` |

The server exports read the saved snapshot, which can miss the last seconds of
edits (see `Textexp.Document.YPersistence`).

## License

Textexp is released under the [MIT license](LICENSE).

The JavaScript served to the browser also bundles BlockNote's "XL" exporters
(`@blocknote/xl-*`), licensed under the GPL-3.0 (or a commercial license):
that bundle as a whole is distributed under the terms of the GPL-3.0, and its
complete source is this repository. BlockNote itself (`@blocknote/core`,
`react`, `mantine`) is under the MPL-2.0.

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
