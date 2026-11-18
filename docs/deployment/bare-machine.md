# Deployment on a bare machine

> **Not tried yet.** What we know of a bare machine, before trying it;
> nothing here was deployed. Still to do: see the
> [to do](../../TODO.md#hosts-to-try-and-document).

What Padocs needs, the emails and the storage of the images:
[Deployment](README.md); every variable: [Configuration](../configuration.md).

A virtual machine just created, at any host taking
[cloud-init](https://cloud-init.io): AWS, Google Cloud, Azure, and the VPS
of Hetzner, Scaleway, OVH or Infomaniak.

## What we expect

A cloud-init file, given when creating the machine, nothing to type on it,
installing:

- Podman and the Quadlet of [Podman](podman.md), with the database and the
  images on the machine's disk;
- Caddy in front, for HTTPS, its certificate from Let's Encrypt.

The same file serves every host; a page per cloud would only tell what
differs (creating the machine, the disk, the firewall):

| Cloud | Machine | Disk | Litestream to |
|---|---|---|---|
| AWS | EC2, or Lightsail, simpler | an EBS volume | S3 |
| Google Cloud | Compute Engine | a persistent disk | Cloud Storage |

Tried on one first. Without Podman, a release and a systemd unit would do
too, with a release built for the machine's system, as for
[YunoHost](yunohost.md).
