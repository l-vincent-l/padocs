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

2026-11-09, 1 CPU, 512 MB, `--find-limit` with `--hold 30s`. A VU that
writes types a word every 0.5 to 1.5 s, one update per word (the editor
sends one per keystroke). "Held" is the last step under the thresholds of
the scenario.

| Test | Held | Broke at | What broke |
|---|---|---|---|
| One document, every VU writing | 100 VUs, propagation p95 15 ms | 200 | propagation p95 4.6 s, CPU 100% |
| One document, 10 writers, the others reading | 600 VUs, propagation p95 37 ms | 800 | joining p95 4.5 s (propagation still 78 ms) |
| Documents of 5 writers, SQLite | 1,500 VUs (300 documents, 1,100 edits/s) | 1,750 | joining p95 2.2 s, CPU 100%, 422 MB |
| Documents of 5 writers, libSQL (Hrana) | 1,000 VUs (200 documents), the most tried | | joining p95 27 ms (SQLite: 14 ms) |
| Search, 200 documents of 1,600 words | 10 VUs, first search p95 0.5 s | 20 | first search p95 3.1 s, next ones 1 s, CPU 100% |

One document: the document's `Yex.DocServer.Worker` applies each edit and
broadcasts it to all the others (`broadcast_from`), one after the other: with
everyone writing, the messages grow as the square of the VUs, 34,000 a
second at 200, and its queue keeps growing (164, then 479, 670, 832 messages,
10 s apart). Applying an edit costs Yjs some 20 µs; the broadcast is the
cost. Merging the edits of a few tens of milliseconds into one broadcast, as
the DocServer already does for the awareness, would divide it.

Readers: joining slows down first, while 200 VUs join in 5 s: each join and
leave also sends a presence diff to everyone in the document (not measured
apart yet).

libSQL runs here in a container next to the application, without the
network latency of Bunny Database, which these numbers leave out: each join
reads the database several times.

Search: each opening of the search modal builds the user's own index of all
the documents they can read (0.5 s of CPU here, about 7 MB), and each search
cuts the snippets of its results.
