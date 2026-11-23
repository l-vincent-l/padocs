# 0012. Interface through Gettext, English msgids, French by default

- **Status**: Accepted
- **Date**: 2026-11-13

## Context

The interface was written in French, while the code, comments and docs are
in English. An English version was wanted.

## Decision

- Every user-facing text goes through `gettext`/`ngettext` with an English
  msgid; changeset messages use `dgettext_noop("errors", ...)`.
- French lives in `priv/gettext/fr`; `mix precommit` fails while the
  extraction is stale.
- The language is the account's choice, else the session's, else
  `Accept-Language`, else French (`PadocsWeb.Locale`). BlockNote follows
  `<html lang>`.

## Consequences

- No French literal in templates or flashes; dates use a translated pattern.
- Tests run in French by default and assert the French texts.
