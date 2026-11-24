# 0017. The administrator role comes from ADMIN_EMAILS, on a confirmed address

- **Status**: Proposed
- **Date**: 2026-11-23

## Context

Anyone may register today, by password, sign-in link or GitHub/GitLab, and
the application has no administrator role: only the LiveDashboard's
credentials (`DASHBOARD_USER`). Closing registrations, invitations,
approval of accounts and allowed email domains all need an administrator.

## Decision

- An account is administrator while its address is in `ADMIN_EMAILS`
  (addresses separated by commas) **and confirmed**, checked on each
  request.
- Removing an address from the variable removes the role at the next
  restart.
- The administrator gets an "Administration" entry in the menu, and the
  LiveDashboard without its own credentials.
- Maybe later, a page to name other administrators, kept in the database,
  the variable still giving the first ones.

## Options set aside

- **The first account registered**: on a new instance, the role would go to
  whoever comes first.
- **An address in the variable without confirmation**: registering first
  with that address, without receiving its emails, would give the role.

## Consequences

- Every way to register counts for the rules that follow (closed
  registrations, invitations, approval, allowed domains), the password, the
  sign-in link and GitHub alike.
- Giving the role takes access to the deployment's environment, which is
  also where the other secrets are set.
