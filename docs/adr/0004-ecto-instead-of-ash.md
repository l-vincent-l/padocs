# 0004. Ecto written by hand instead of Ash

- **Status**: Accepted
- **Date**: 2026-10-26

## Context

The first version used Ash, AshAuthentication, AshPhoenix, AshAdmin and
AshSqlite. A comparison branch (`sans-ash`) rewrote it with plain Ecto, to
weigh the two.

## Decision

Ash was replaced by hand-written Ecto (merged in PR #1):

- the accounts come from `phx.gen.auth` (password, magic link, reset,
  confirmation, sessions in the database), with
  [Assent](https://hex.pm/packages/assent) for GitHub and GitLab, at the
  same callback URLs;
- the access rights are checked in the queries and one Policy module (see
  [0006](0006-access-rights-policy-in-docserver.md));
- the sign-in pages are controllers and HEEx templates.

## Consequences

- The `tokens` table of the JWTs gave way to `users_tokens`: the open
  sessions were signed out once.
- Fewer dependencies, and code that follows the Phoenix generators and
  guides; in exchange, no generated admin.
