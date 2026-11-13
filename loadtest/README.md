# Load tests

With [Stampede](https://hex.pm/packages/stampede) (a dev dependency), against
the production image of the application, run locally in a container sized
like the Fly.io machine (1 CPU, 512 MB).

    loadtest/app.sh --build          # builds the image, starts it, seeds it
    LOADTEST_DOCUMENTS=<ids> mix stampede.run loadtest/editing.exs
    loadtest/app.sh --stop

`app.sh` prints the ids of the test documents, separated by commas. The
database is SQLite, or libSQL with `LOADTEST_DATABASE=hrana` (each its own
image, built by `--build`); it starts empty on each start. Each script tells
its options in its header.

| File | |
|---|---|
| `app.sh` | starts the container and runs `seed.exs` in it |
| `seed.exs` | accounts `loadtest-<n>@example.com` (password `loadtest-password`) and documents shared with all of them |
| `session.exs` | the scenarios' environment and sign-in |
| `editing.exs` | editors in documents: one document, or many, all writing or a few |
| `search.exs` | users searching all the documents, from the search modal |
| `top.exs` | the server's longest message queues, during a test: `docker exec textexp-loadtest /app/bin/textexp rpc 'Code.eval_file("/loadtest/top.exs")'` |

Stampede's options apply, e.g. `--vus 100 --duration 2m`, `--find-limit`,
`--dashboard` (http://127.0.0.1:4040), `--html report.html`. VUs beyond
`LOADTEST_USERS` (50, as seeded) share the accounts. The application's own
LiveDashboard is at http://localhost:4000/admin/dashboard when `app.sh` was
started with `DASHBOARD_USER` and `DASHBOARD_PASSWORD` set.

## Results

In [PERFORMANCES.md](../PERFORMANCES.md).
