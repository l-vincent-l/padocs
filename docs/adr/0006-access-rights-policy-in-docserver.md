# 0006. Access rights in one Policy, held live by the DocServer

- **Status**: Accepted
- **Date**: 2026-10-26 (roles since 2026-10-21)

## Context

Documents are shared per person with a role (owner, editor, viewer, see
[concepts](../concepts.md#roles-and-sharing)). A change of role had to
apply at once to people with the document open, not only at their next
join.

## Decision

- `Padocs.Document.Policy.can?(role, action)` is the single, pure rule for
  `:read`, `:write` and `:share`.
- Listings stay filtered in SQL (`readable_by`); an action reads the role,
  then checks the Policy, in one transaction.
- While it runs, the DocServer holds the rights, through the generic
  `YPhoenix.Access` behaviour implemented by `Padocs.Document.Access`: it
  subscribes to the members topic before loading, answers joins, and tells
  the channels when a permission changes (a viewer becomes read-only, a
  removed member's channel stops). The LiveView redirects on a change.

## Consequences

- New access checks go through the Policy; Padocs' roles stay out of
  `lib/y_phoenix`.
- Known gap: another document's entry in the sidebar is not removed when
  access to it is withdrawn.
