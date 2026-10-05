install_podman_offline
======================

Installs Podman and a compose provider on RHEL 9 with no internet access, for
running Harbor on Podman.

Podman, `container-selinux` and `policycoreutils-python-utils` come from RHEL
through the environment's yum repository. The compose provider is the only
piece outside RHEL:

| `podman_offline_compose_provider` | Source | Notes |
|---|---|---|
| `podman-compose` (default) | EPEL, from Nexus's yum repo or as staged RPMs | Runs everything through the `podman` CLI |
| `docker-compose` | Docker's static binary, staged with a checksum | Talks to Podman's Docker-compatible API socket; no EPEL needed |

Red Hat supports Podman itself; neither compose provider is a Red Hat package.

The role also checks that Podman uses the netavark network stack, because
Harbor's containers find each other by name through aardvark-dns. The
transfer only carries podman-compose and python3-dotenv; everything else comes
from the server's own repos, and only packages the server is missing are
installed from the transfer. Installed RHEL packages are never upgraded or
replaced from it.

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `podman_offline_compose_provider` | from `harbor_podman_compose_provider` | Which provider to install |
| `podman_offline_compose_source` | `staged` | `staged` RPMs or `yum` (local EPEL mirror) |
| `podman_offline_rpm_path` | `harbor/podman` | Sub-path under `artifact_staging` |
| `podman_offline_gpg_key` | `harbor/RPM-GPG-KEY-EPEL-9` | EPEL's signing key from the transfer, under `artifact_staging`; imported before staged RPMs are installed |
| `podman_offline_docker_compose_file` | `harbor/docker-compose-linux-x86_64` | Sub-path under `artifact_staging` |
| `podman_offline_docker_compose_sha256` | `""` | Checked when set; staging writes it to the manifest |

`desired_state: absent` removes the compose provider but leaves Podman in place.

License
-------

GPL-3.0-only
