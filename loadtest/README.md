# Load tests

With [Stampede](https://hex.pm/packages/stampede) (a dev dependency), against
the production image of the application, run locally in a container sized
like the Fly.io machine (1 CPU, 512 MB, SQLite).

    loadtest/app.sh --build          # builds the image, starts it, seeds it
    LOADTEST_DOCUMENT=<id> mix stampede.run loadtest/one_document.exs
    loadtest/app.sh --stop

`app.sh` prints the id of the test document. Its database is in memory: it
starts empty on each start. Without `--build`, the image is the last one
built.

| File | |
|---|---|
| `app.sh` | starts the container and runs `seed.exs` in it |
| `seed.exs` | accounts `loadtest-<n>@example.com` (password `loadtest-password`) and a document shared with all of them |
| `one_document.exs` | many editors in one document (see its header) |
| `top.exs` | the server's longest message queues, during a test: `docker exec textexp-loadtest /app/bin/textexp rpc 'Code.eval_file("/loadtest/top.exs")'` |

Stampede's options apply, e.g. `--vus 100 --duration 2m`, `--find-limit`,
`--dashboard` (http://127.0.0.1:4040), `--html report.html`. VUs beyond
`LOADTEST_USERS` (50, as seeded) share the accounts. The application's own
LiveDashboard is at http://localhost:4000/admin/dashboard when `app.sh` was
started with `DASHBOARD_USER` and `DASHBOARD_PASSWORD` set.

## Results

2026-11-09, `one_document.exs`, each VU typing a word every 0.5 to 1.5 s,
`--find-limit --start 100 --step 100 --hold 30s`, 1 CPU, 512 MB, SQLite:

| VUs | edits/s | `channel.join` p95 | `yjs.sync` p95 | `yjs.propagation` p95 | |
|---:|---:|---:|---:|---:|---|
| 50 | 43 | 6 ms | 58 ms | 14 ms | held (2 min) |
| 100 | ~85 | 13 ms | 21 ms | 15 ms | held |
| 200 | ~170 | 155 ms | 185 ms | 4.6 s | over the limit |

At 200 the server is at 100% of its CPU and the queue of the document's
`Yex.DocServer.Worker` keeps growing (164, then 479, 670, 832 messages, 10 s
apart): it applies each edit and broadcasts it to the 199 others itself
(`broadcast_from`, 34,000 messages a second), one after the other. Memory
stays low (under 170 MB).
