install_harbor
==============

Installs Harbor from its official offline installer and runs it under systemd,
on either container runtime:

| `harbor_container_runtime` | How Harbor runs |
|---|---|
| `podman` (default) | Images loaded with `podman load`; Harbor's own `prepare` container generates the configuration; the generated compose file is adapted for Podman and run by `podman-compose` (or `docker-compose` against Podman's API socket) |
| `docker` | Harbor's `install.sh`, unchanged |

What changes for Podman, and why:

| Harbor expects | Podman reality | What the role does |
|---|---|---|
| `install.sh` checks for Docker and Compose | No Docker on the host | Runs the installer's steps directly with Podman |
| `syslog` log driver to a `log` container | Podman supports `k8s-file`, `journald`, `none`, `passthrough` | Drops the `log` service; every service logs to journald |
| Bind-mount sources created on demand | Podman errors on a missing source | Creates them before `prepare` |
| SELinux labels only where volumes say `:z` | Podman enforces SELinux on every bind mount | Labels `data_volume` and `common/` as `container_file_t` |

`harbor.yml` is created from the installer's `harbor.yml.tmpl`, and only the
hostname, ports, TLS paths, passwords and data volume change. A hand-edited
`harbor.yml` is never overwritten; a changed value regenerates the configuration
and restarts Harbor.

The runtime it deployed on is recorded in `.installed_runtime`. A later run on
the other runtime stops with a pointer to `remove_registry.yml`,
so Podman and Docker never hold the same ports and data at once. The admin
password is seeded on the first deploy only; after that it is changed in Harbor
and kept in step in the vault.

Harbor serves a copy of its certificate from `<data_volume>/secret/cert/`. With
`harbor_cert_sync: true` the role adds `harbor-cert-sync.path`, which watches
`harbor_tls_cert` and, on a renewal, copies the certificate and key across and
restarts `nginx`.

The installed release is recorded in `.installed_version`. When `harbor_version`
changes, `tasks/upgrade.yml` stops Harbor, copies the database directory, moves
the old release aside, unpacks the new one and migrates `harbor.yml` with the new
`prepare` image; the normal install tasks then bring the new release up.

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `harbor_container_runtime` | `podman` | `podman` or `docker` |
| `harbor_podman_compose_provider` | `podman-compose` | `podman-compose` (EPEL) or `docker-compose` (static binary on Podman's API socket) |
| `harbor_podman_log_driver` | `journald` | `journald` or `k8s-file` |
| `harbor_hostname` | | **Required**, set in host_vars |
| `harbor_admin_password` / `harbor_db_password` | | **Required**, from the vault |
| `harbor_data_volume` | `/data` | Registry storage |
| `harbor_manage_selinux` | `true` | Label Harbor's paths for containers |
| `harbor_data_require_mount` | `false` | Stop unless `harbor_data_volume` is its own mount |
| `harbor_cert_sync` | `true` | Carry a renewed certificate into Harbor and restart `nginx` |
| `harbor_purge_install` / `harbor_purge_data` | `false` | Extra clean-up for `desired_state: absent`: delete the install directory / empty the data volume (a mount point stays mounted) |

Requirements
------------

`community.general` (for `sefcontext`) and `ansible.posix`. Runs after
`install_podman_offline` or `install_docker_offline`, `download_harbor_artifacts`
and `configure_harbor_tls`.

License
-------

GPL-3.0-only
