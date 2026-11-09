#!/usr/bin/env bash
# Starts the application for the load tests: its production image (target
# `final`, SQLite), in a container sized like the Fly.io machine (1 CPU,
# 512 MB), its database in memory; then seeds it (loadtest/seed.exs) and
# prints the id of the test document.
#
#   loadtest/app.sh            # starts, or restarts, the container
#   loadtest/app.sh --build    # builds the image first
#   loadtest/app.sh --stop     # stops it
#
# Environment: LOADTEST_USERS (50), LOADTEST_PORT (4000), LOADTEST_CPUS (1),
# LOADTEST_MEMORY (512m); DASHBOARD_USER and DASHBOARD_PASSWORD, passed on to
# open the LiveDashboard (/admin/dashboard).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
image=textexp:loadtest
name=textexp-loadtest
users="${LOADTEST_USERS:-50}"
port="${LOADTEST_PORT:-4000}"

case "${1:-}" in
  --stop)
    docker rm -f "$name" >/dev/null
    exit 0
    ;;
  --build)
    docker build --target final -t "$image" "$root"
    ;;
esac

docker rm -f "$name" >/dev/null 2>&1 || true

# The open files limit is set: Docker's default is so high that the Erlang
# node of `bin/textexp rpc`, which has no `+Q`, sizes its port table on it
# and takes gigabytes.
docker run -d --name "$name" \
  --cpus "${LOADTEST_CPUS:-1}" --memory "${LOADTEST_MEMORY:-512m}" \
  -p "127.0.0.1:$port:4000" \
  --ulimit nofile=65536:65536 \
  --tmpfs /data:mode=1777 \
  -v "$root/loadtest:/loadtest:ro" \
  -e SECRET_KEY_BASE="$(head -c 48 /dev/urandom | base64 -w0)" \
  -e PHX_HOST=localhost \
  -e DATABASE_PATH=/data/textexp.db \
  -e DASHBOARD_USER -e DASHBOARD_PASSWORD \
  "$image" >/dev/null

echo "Waiting for http://localhost:$port ..." >&2
for _ in $(seq 1 60); do
  if curl -sf -o /dev/null "http://localhost:$port/sign-in"; then
    break
  fi
  sleep 1
done

echo "Seeding $users accounts ..." >&2
docker exec "$name" /app/bin/textexp rpc \
  "Code.eval_file(\"/loadtest/seed.exs\"); Loadtest.Seed.run($users)" | tail -1
