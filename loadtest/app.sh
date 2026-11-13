#!/usr/bin/env bash
# Starts the application for the load tests: its production image (target
# `final`), in a container sized like the Fly.io machine (1 CPU, 512 MB); then
# seeds it (loadtest/seed.exs) and prints the ids of the test documents,
# separated by commas.
#
# The database is SQLite, in memory, or with LOADTEST_DATABASE=hrana a libSQL
# server in a container of its own (sqld, as Bunny Database runs), reached
# over HTTP by the Hrana adapter. Either way it starts empty.
#
#   loadtest/app.sh            # starts, or restarts, the containers
#   loadtest/app.sh --build    # builds the image first
#   loadtest/app.sh --stop     # stops them
#
# Environment: LOADTEST_USERS (50), LOADTEST_DOCUMENT_COUNT (1),
# LOADTEST_PARAGRAPHS (1, see seed.exs),
# LOADTEST_DATABASE (sqlite3 or hrana), LOADTEST_PORT (4000), LOADTEST_CPUS
# (1), LOADTEST_MEMORY (512m); DASHBOARD_USER and DASHBOARD_PASSWORD, passed
# on to open the LiveDashboard (/admin/dashboard).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
database="${LOADTEST_DATABASE:-sqlite3}"
name=padocs-loadtest
libsql=padocs-loadtest-libsql
network=padocs-loadtest
users="${LOADTEST_USERS:-50}"
documents="${LOADTEST_DOCUMENT_COUNT:-1}"
paragraphs="${LOADTEST_PARAGRAPHS:-1}"
port="${LOADTEST_PORT:-4000}"

case "$database" in
  sqlite3) image=padocs:loadtest ;;
  hrana) image=padocs:loadtest-hrana ;;
  *) echo "LOADTEST_DATABASE: sqlite3 or hrana" >&2; exit 1 ;;
esac

case "${1:-}" in
  --stop)
    docker rm -f "$name" "$libsql" >/dev/null 2>&1 || true
    exit 0
    ;;
  --build)
    docker build --target final --build-arg DATABASE_ADAPTER="$database" -t "$image" "$root"
    ;;
esac

docker rm -f "$name" "$libsql" >/dev/null 2>&1 || true
docker network inspect "$network" >/dev/null 2>&1 || docker network create "$network" >/dev/null

database_env=(-e DATABASE_PATH=/data/padocs.db)

if [ "$database" = hrana ]; then
  # its port is published only to wait for it here, before the migrations
  docker run -d --name "$libsql" --network "$network" -p 127.0.0.1:18080:8080 \
    ghcr.io/tursodatabase/libsql-server:latest >/dev/null

  for _ in $(seq 1 30); do
    if curl -sf -o /dev/null http://127.0.0.1:18080/health; then
      break
    fi
    sleep 1
  done

  database_env=(-e BUNNY_DATABASE_URL="http://$libsql:8080")
fi

# The open files limit is set: Docker's default is so high that the Erlang
# node of `bin/padocs rpc`, which has no `+Q`, sizes its port table on it
# and takes gigabytes.
docker run -d --name "$name" --network "$network" \
  --cpus "${LOADTEST_CPUS:-1}" --memory "${LOADTEST_MEMORY:-512m}" \
  -p "127.0.0.1:$port:4000" \
  --ulimit nofile=65536:65536 \
  --tmpfs /data:mode=1777 \
  -v "$root/loadtest:/loadtest:ro" \
  -e SECRET_KEY_BASE="$(head -c 48 /dev/urandom | base64 -w0)" \
  -e PHX_HOST=localhost \
  "${database_env[@]}" \
  -e DASHBOARD_USER -e DASHBOARD_PASSWORD \
  "$image" >/dev/null

echo "Waiting for http://localhost:$port ..." >&2
for _ in $(seq 1 60); do
  if curl -sf -o /dev/null "http://localhost:$port/sign-in"; then
    break
  fi
  sleep 1
done

echo "Seeding $users accounts and $documents documents ($database) ..." >&2
docker exec "$name" /app/bin/padocs rpc \
  "Code.eval_file(\"/loadtest/seed.exs\"); Loadtest.Seed.run($users, $documents, $paragraphs)" | tail -1
