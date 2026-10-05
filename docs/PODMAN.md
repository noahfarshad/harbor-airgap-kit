# Harbor on Podman (RHEL 9)

How the kit runs Harbor on Podman, why each step is there, and where support
starts and stops.

## Support position

Harbor's installer is written for Docker Engine and Compose. Podman support has
been requested upstream for years and is still open as pull requests
(goharbor/harbor #22451 and #23881). Until one lands, Harbor on Podman is a
community-proven configuration rather than an upstream-supported one:

- The Harbor images are unchanged: same offline installer, same containers.
- The adaptation is small and lives in `install_harbor` (`install_podman.yml`,
  `podman_prepare.yml`, `templates/podman-compose.yml.j2`).
- Pin the Harbor release in `harbor_artifacts.yml` and prove every new release
  in the lowest environment before it moves.
- Red Hat supports Podman itself. Neither compose provider is a Red Hat package.

## What the role does differently

| Step | Docker | Podman |
|---|---|---|
| Load images | `install.sh` → `docker load` | `podman load -i harbor.v<version>.tar.gz` |
| Generate configuration | `install.sh` → `./prepare` → `docker run goharbor/prepare` | `podman run --privileged goharbor/prepare` with the same mounts |
| Compose file | Used as generated | `podman-compose.yml` written from it: `log` service removed, every service logs to journald |
| SELinux | Not enforced on Docker bind mounts by default | `data_volume` and `common/` labelled `container_file_t` |
| Run | `docker compose up -d` | systemd unit → `podman-compose up -d` |

Why the compose file changes: Harbor routes every service's logs through the
`syslog` log driver to its own `log` container. Podman's log drivers are
`k8s-file`, `journald`, `none` and `passthrough`, so there's no `syslog`.

## Compose provider

| `harbor_podman_compose_provider` | Comes from | Choose it when |
|---|---|---|
| `podman-compose` (default) | EPEL, carried in the transfer and served from Nexus's yum repo | EPEL content is allowed |
| `docker-compose` | Docker's static binary, run against Podman's API socket | EPEL is not allowed |

Both read the same `podman-compose.yml`.

## Operating it

```bash
systemctl status harbor                       # the unit wraps the compose provider
podman ps --filter label=com.docker.compose.project=harbor
journalctl CONTAINER_NAME=harbor-core -f      # per-service logs
podman logs harbor-jobservice
```

Restart after a configuration change: re-run `make build-registry`. A changed
value in `harbor.yml` regenerates the configuration and restarts the unit.

## Troubleshooting

| Symptom | Check |
|---|---|
| A container exits with permission denied on a bind mount | `ausearch -m avc -ts recent`; re-run the play so `restorecon` relabels |
| Services can't reach each other by name | `podman network inspect harbor_harbor`. DNS has to be enabled (it is for networks compose creates) |
| `prepare` fails with a missing path | The data volume and `common/config` have to exist before the run. The role creates them |
| Image pull attempts in the logs | `podman images \| grep goharbor`. The release images have to be loaded; nothing gets pulled |
| Harbor answers on the host but not from other machines, after `firewall-cmd --reload` | A firewalld reload drops Podman's port forwarding. `podman network reload --all` restores it now; the play enables `netavark-firewalld-reload.service`, which restores it after every reload |
| The play stops at "Stop unless Podman uses netavark" | This host runs Podman on the older CNI network stack, which gives containers no name resolution here. Set `network_backend = "netavark"` in `/etc/containers/containers.conf`; switching needs `podman system reset`, which removes existing containers and images |

## Certificate renewal

Harbor's `prepare` step copies the certificate into
`<data_volume>/secret/cert/` and `nginx` reads it from there, so a certificate
renewed in place by certmonger would not reach Harbor on its own.
`install_harbor` adds two systemd units for this (`harbor_cert_sync: true`):

| Unit | Does |
|---|---|
| `harbor-cert-sync.path` | Watches `harbor_tls_cert` |
| `harbor-cert-sync.service` | Copies the certificate and key into `secret/cert/` (owner 10000, mode 0644) and restarts `nginx` |

```bash
systemctl status harbor-cert-sync.path
journalctl -u harbor-cert-sync.service
```

## Rolling back and switching runtime

`make remove-registry` stops Harbor, removes its units and generated compose
files, and leaves `harbor.yml`, the data and the runtime in place. The kit never
touches a registry you already have, so an old one keeps serving until you
retire it.

Moving to Docker is a remove and a rebuild, not just a setting. Docker has to be
available first, either from the server's own repos or from the transfer
(`docker_ce.enabled: true` in `kit.yml` and `docker_offline_source: staged`).
Then run `make remove-registry`, change `harbor_container_runtime`, and run
`make build-registry`. `install_harbor` won't deploy on a different runtime from
the one it recorded until the remove has run.
