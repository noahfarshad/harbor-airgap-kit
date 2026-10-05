lab_nexus
=========

Lab only. Runs Nexus Repository 3 in a Podman container that systemd manages
through a Quadlet unit (`/etc/containers/systemd/nexus.container`, which
becomes `nexus.service`). Its data lives in the `nexus-data` volume. It waits
until Nexus accepts writes, then hands the generated first-start admin password
to `configure_nexus`, which replaces it with the one in the vault.

| Variable | Default | What it is |
|---|---|---|
| `lab_nexus_image` | `docker.io/sonatype/nexus3:3.96.4` | Pinned. Use `mirror.gcr.io/sonatype/nexus3:3.96.4` if Docker Hub rate-limits you |
| `lab_nexus_port` | `8081` | Published on this machine |
| `lab_nexus_heap` | `1g` | Heap and direct memory each |
| `lab_nexus_purge_data` | `false` | `desired_state: absent` only; `true` deletes the volume |
