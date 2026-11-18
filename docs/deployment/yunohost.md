# YunoHost

> **Not tried yet.** What we know of a YunoHost package, before trying it;
> nothing here was deployed. Still to do: see the
> [to do](../../TODO.md#hosts-to-try-and-document).

What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

[YunoHost](https://yunohost.org) installs applications on a server of yours
from packages, with its sign-in, backups and upgrades.

## What we expect

Not a page of instructions but a package of its own, `padocs_ynh`:

- installing a precompiled release, one per architecture, built by a
  workflow (YunoHost does not run Docker);
- a systemd service, nginx in front (YunoHost's), the database and the
  images in the application's data folder, saved by YunoHost's backups;
- maybe YunoHost's sign-in (SSO) for the accounts.
