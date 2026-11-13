# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.4-erlang-29.0.6-debian-trixie-20261005-slim
#   - https://hub.docker.com/_/debian/tags?name=trixie-20261005-slim - for the runner image
#     E.g.: docker.io/debian:trixie-20261005-slim
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker?repo=hexpm/elixir&os=debian&sort=elixir_version,erlang_version,os_version
#
# We suggest using the same Debian version for both the builder and runner images.
#
# We suggest Debian/Ubuntu instead of Alpine to avoid production compatibility issues
# (such as DNS resolution failures, and dynamically linked NIFs/precompiled binaries).
#
# For finding packages in Debian, search on https://packages.debian.org/.

ARG ELIXIR_VERSION=1.20.4
ARG OTP_VERSION=29.0.6
ARG DEBIAN_VERSION=trixie-20261005-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies (Rust builds tantivy_ex's NIF, see mix.exs)
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm curl ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Rust from rustup: Debian's (1.85 in trixie) is older than what Tantivy 0.26
# and its dependencies need (1.90)
ARG RUST_VERSION=1.91.0
ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
  | sh -s -- -y --profile minimal --default-toolchain ${RUST_VERSION} --no-modify-path

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# The database: "sqlite3" (a local file) or "hrana" (a libSQL server, e.g.
# Bunny Database), see config/config.exs. Kept in the image, as the release
# reads it again when it starts.
ARG DATABASE_ADAPTER=sqlite3
ENV DATABASE_ADAPTER=${DATABASE_ADAPTER}

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

# install npm dependencies (cached unless package files change)
COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --prefix assets

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Modules are loaded on first use instead of all at boot (embedded mode): the
# deps (Ash above all) hold ~4500 modules, most of them never called, whose
# code and JIT output would take ~270 MB more memory.
ENV RELEASE_MODE="interactive"

ARG DATABASE_ADAPTER=sqlite3
ENV DATABASE_ADAPTER=${DATABASE_ADAPTER}

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/padocs ./

# Fly.io image (`build-target = "fly"` in fly.toml): a local SQLite file on a
# volume, replicated to S3 (Tigris) by Litestream. It starts as root to hand the
# volume, mounted as root, over to nobody; bin/fly_start then drops privileges.
FROM runtime AS fly

COPY --from=docker.io/litestream/litestream:0.5.17-scratch /usr/local/bin/litestream /usr/local/bin/litestream
COPY litestream.yml /etc/litestream.yml

CMD ["/app/bin/fly_start"]

# Default image: the SQLite file at DATABASE_PATH, without replication, or, with
# DATABASE_ADAPTER=hrana, a libSQL server (Bunny Database).
FROM runtime AS final

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

# run pending migrations, then start the server
CMD ["/bin/sh", "-c", "/app/bin/migrate && exec /app/bin/server"]
