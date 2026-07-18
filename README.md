# Fedora CoreOS Configs

This repository contains the full configurations of my 'server' hosts. It uses
[Butane](https://coreos.github.io/butane/) to build the host's Ignition config,
and [Copier](https://copier.readthedocs.io/) with Jinja to render host-specific
files, and Podman Quadlet units to run the service stack.

The current hosts are:

- `vps1`: a 4C/8GB VPS running most of my apps/containers.
  This is the only publicly reachable host in my network.

This is a personal configuration rather than a turnkey deployment. It can be
useful as a reference, but hostnames, addresses, domains, credentials, and
service choices are specific to my environment.

## Layout

- `build-butane.sh` renders a host's Butane template and compiles it to
  Ignition.
- `build-services.sh` renders and deploys a host's rootful and rootless Quadlet
  trees.
- `shared/` contains shell helpers and configuration copied into the C&C (command & control)
  containers of all hosts.
- `HOST/butane/` (eg. `vps1/butane/`) contains the Fedora CoreOS provisioning template and generated
  `config.ign`.
- `HOST/services/root/` contains privileged host services, including the C&C
  container and Tailscale client.
- `HOST/services/rootless/` contains the application stack: Caddy, Blocky,
  Headscale/Headplane, Pocket ID, TinyAuth, Glance, Vaultwarden, Tuwunel,
  Rybbit, a croc relay, and several personal projects.
- `HOST/volumes/` holds persistent service data and is intentionally ignored by
  Git.

Rendered service trees are written to `HOST/services-dist/` and are also
ignored by Git.

## Secrets

Secrets live in `secrets.yaml` and are encrypted with
[SOPS](https://getsops.io/) and age. The corresponding age identity must be
available at:

```text
~/.config/sops/age/keys.txt
```

Only keys prefixed with `enc_priv_` are encrypted. During rendering they are
exposed to templates as `priv_...` variables. Private variables are explicitly
rejected by the Butane build, so credentials cannot be embedded in the
generated Ignition config by accident. `build-butane.sh` extracts only the
unencrypted public variables directly from `secrets.yaml`; it never invokes
SOPS or mounts the age identity.

Keep the age identity out of this repository and back it up separately. The
ignored `HOST/volumes/` directories also need their own backup strategy.

## Build the Ignition config

Both build scripts need Podman. `build-services.sh` also needs the age identity
file, but SOPS and age are installed and used inside Podman.
The Ignition config also installs SOPS and age on the host for
interactive administration, but the build scripts do not depend on those host
binaries. Copier and Butane do not need to be installed directly.

```sh
./build-butane.sh HOST
```

The result is written to `HOST/butane/config.ign`. Supply that file when
provisioning Fedora CoreOS through the hosting provider or installer. On first
boot, the Ignition config:

- configures the `core` user and SSH access;
- applies the host network and system settings;
- layers the required host packages;
- installs SOPS; and
- clones this repository to `/home/core/infra-template`.

## Render and deploy services

Right after installing and the reboot caused by `rpm-ostree install`, place the
age identity at the path shown above. Then run the deployment from that host:

```sh
cd ~/infra-template
./build-services.sh HOST
```

The script refuses to deploy unless its host argument matches `/etc/hostname`.
It mounts `secrets.yaml` and the age identity read-only into an ephemeral
container, installs SOPS and age there, decrypts the data inside the container,
and renders all Jinja templates. The decrypted temporary file disappears with
the container. The script then synchronizes the resulting Quadlet files to:

```text
/etc/containers/systemd/HOST-root/
~/.config/containers/systemd/HOST-rootless/
```

It then reloads the system and user systemd managers. Units can be managed with
the usual commands, for example:

```sh
sudo systemctl start cnc.service
systemctl --user start caddy.service
```

The C&C container includes helper commands for day-to-day administration:

- `list-services`, `start-services`, and `stop-services` manage the complete
  rootful/rootless stack.
- `update-services` pulls the repository and reruns `build-services.sh` for the
  current host.
- `update-cnc` rebuilds the administration container and offers to restart it.
- `run-host` and `run-host-root` execute commands in the Fedora CoreOS host
  namespaces from inside the C&C container.

## Updating

For a normal configuration update on the server:

```sh
cd ~/infra-template
git pull --ff-only
./build-services.sh HOST
```

Rebuilding the C&C container requires a restart and will reset its container-local state (including `/home` inside the container). Its
persistent data (`/data` inside the container) belongs under `HOST/volumes/cnc-data`.
