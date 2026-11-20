# Hosts not considered

Hosts set aside for Padocs, against what it needs (see
[Choosing a host](README.md#choosing-a-host)): a container running all the
time, WebSockets, one instance writing, and a persistent disk, or else an S3
easy to get alongside. Their offers change: a reason may stop holding, then
the host is worth another look.

| Host | Why not |
|---|---|
| Vercel, Netlify, Cloudflare Workers | Short functions started for each request, not an application running all the time with a server per open document. |
| Google Cloud Run | No persistent disk, and WebSockets cut after 60 minutes at most: the editors would reconnect regularly. A Compute Engine machine suits instead: [a bare machine](bare-machine.md). |
| Heroku | An ephemeral disk, so libSQL elsewhere, and S3 elsewhere for the images; expensive for what it gives. |
| Gigalixir | Made for Elixir, but around PostgreSQL, which Padocs does not use, with an ephemeral disk. |
| Northflank | Docker and volumes would do, but a heavy platform for one application. |
| Scalingo | No disk (its own SQLite guide says so), no S3, no libSQL: two more providers. It builds with buildpacks, the Elixir one lacking Node (for the editor). Its SecNumCloud region (`osc-secnum-fr1`) could make it worth it for French public bodies, if one asks. |
