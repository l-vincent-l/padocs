# Deployment on a bare machine

A virtual machine just created, at any host taking
[cloud-init](https://cloud-init.io) user data: AWS, Google Cloud, Azure, and
the VPS of Hetzner, Scaleway, OVH or Infomaniak. What Padocs needs, the
emails and the storage of the images: [Deployment](README.md); every
variable: [Configuration](../configuration.md).

`cloud-init.yaml`, at the root of the repository, given when creating the
machine, sets it all up at its first boot, nothing to type on it:

- the system's packages updated, and their security updates installed every
  day (`unattended-upgrades`);
- [Podman](https://podman.io), running the image that GitHub builds on every
  push to main, `ghcr.io/l-vincent-l/padocs:sqlite`, as a systemd service: a
  Quadlet, as in [Podman](podman.md), but for the whole system. The database
  and the images are on a volume of the machine's disk;
- `SECRET_KEY_BASE` generated once, kept in a Podman secret;
- [Caddy](https://caddyserver.com) in front, for HTTPS, its certificate from
  Let's Encrypt;
- as an option, [Litestream](litestream.md), streaming the database to S3
  and restoring it on a new machine.

No image is built on the machine: 1 GB of memory is plenty: with Padocs,
Caddy and Litestream running, the machine uses about 350 MB, the system
included.

Tried with Debian 13 in a local virtual machine (qemu, cloud-init's NoCloud
datasource), Caddy with its own certificates in place of Let's Encrypt, and
Litestream to a local S3 (SeaweedFS). The service, Caddy and the secret
survived a reboot, the WebSockets went through Caddy, and a new machine with
an empty disk got the database back from the bucket. Not yet tried at a
cloud.

## Before creating the machine

1. **The domain.** Point it to the machine's address with an `A` record
   (and `AAAA` for IPv6). Most hosts give the address once the machine
   exists: create the machine, then set the record. Caddy retries the
   certificate until the domain points to it.
2. **The file.** Replace `docs.example.org`, the domain written twice in it
   (for Padocs and for Caddy), with yours:

   ```sh
   sed 's/docs\.example\.org/docs.my-domain.org/g' cloud-init.yaml > user-data.yaml
   ```

   Other variables (images on S3, GitHub sign-in, the dashboard…) go on more
   `Environment=` lines of `padocs.container`, in the file. For Litestream,
   see [below](#backups-with-litestream).
3. **The firewall.** Open ports 22 (SSH), 80 and 443 (HTTP, HTTPS). Caddy
   needs 80 for the certificate and to redirect to HTTPS. Padocs listens on
   127.0.0.1:4000 only.

## Create the machine

Use Debian 13 with your SSH key, and give `user-data.yaml` as the user data:

| Host | Where to give the file |
|---|---|
| AWS EC2 | **Advanced details** → **User data**, or `aws ec2 run-instances --user-data file://user-data.yaml` |
| Google Cloud | **Management** → **Metadata**, key `user-data`, or `gcloud compute instances create --metadata-from-file=user-data=user-data.yaml` |
| Azure | **Advanced** → **Custom data**, or `az vm create --custom-data user-data.yaml` |
| Hetzner Cloud | **Cloud config**, or `hcloud server create --user-data-from-file user-data.yaml` |
| Scaleway Instances | **Advanced options** → **Cloud-init**, or `scw instance server create cloud-init=@user-data.yaml` |
| OVHcloud Public Cloud | **Post-installation script** |

The first boot takes a few minutes: the updates, the packages, then the
image pulled. Then Padocs answers at `https://docs.my-domain.org`.

## On the machine

```sh
sudo cloud-init status --wait               # done, or the error
sudo journalctl -u padocs -f                # the logs, and the emails while no provider is configured
sudo journalctl -u caddy                    # the certificate
sudo systemctl restart padocs
```

The service's file is `/etc/containers/systemd/padocs.container`. After
changing it, run `sudo systemctl daemon-reload && sudo systemctl restart padocs`.

## Updates

`podman-auto-update.timer` checks the image on ghcr.io once a day. When main
has moved, it pulls the new image and restarts Padocs with it (the
migrations run at start). If the new image does not start, it goes back to
the previous one. To update now, run `sudo podman auto-update`. To see what
it would do, run `sudo podman auto-update --dry-run`.

To choose when to update instead, pin a commit,
`Image=ghcr.io/l-vincent-l/padocs:sqlite-<commit>`, and remove
`AutoUpdate=registry`.

## Backups

The volume `padocs-data` holds the database and the images.
`sudo podman volume inspect padocs-data` shows where it is on the disk.
Without Litestream, the simplest is the host's daily snapshots of the disk.
You can also copy the volume while the service is stopped, with
`sudo podman volume export padocs-data > padocs-data.tar`. Stop the service
first: a copy of a database being written may not open.

### Backups with Litestream

[Litestream](litestream.md) streams the database to an S3 bucket as it is
written, about a second behind. A new machine given the same file restores
the database from the bucket before Padocs starts. The images are not in
the database: keep them in a bucket too (`FILES_S3_BUCKET`, see [Storage of
the images](README.md#storage-of-the-images)), or count on the disk's
snapshots for them.

In `cloud-init.yaml`, the lines for Litestream start with `#L `. Uncomment
them as you replace the domain:

```sh
sed -e 's/docs\.example\.org/docs.my-domain.org/g' -e 's/^\( *\)#L /\1/' \
  cloud-init.yaml > user-data.yaml
```

then fill in, in `user-data.yaml`:

- the replica's URL, in `/etc/litestream.yml`:
  `s3://<bucket>/padocs.db?endpoint=<the S3's address>&region=<region>`.
  For AWS S3 itself, leave out `endpoint`;
- the bucket's keys, in `/etc/litestream.env`, a file readable by root only.

Litestream then runs in a container of its own (`litestream.service`, image
`litestream/litestream:0.5.17`), beside that of Padocs, on the same volume,
both as `nobody`:

- **before Padocs starts**, it restores the database when the disk holds
  none and the bucket holds a replica
  (`litestream restore -if-db-not-exists -if-replica-exists`). On a new
  machine with an empty bucket, Padocs starts from an empty database;
- **while Padocs runs**, it streams every write to the bucket;
- **on stop**, systemd stops Padocs first, then Litestream, which syncs
  one last time.

```sh
sudo journalctl -u litestream -f
sudo podman exec litestream litestream ltx /data/padocs.db   # the files of the replica
```

To restore to an earlier point, see [Restore](litestream.md#restore). Stop
both services first, `sudo systemctl stop padocs litestream`.

**One machine at a time.** Two machines given the same bucket would each
write their own database to it, and the replica would be corrupted. Before
creating a new machine on the same bucket, stop the old one, or destroy it.
