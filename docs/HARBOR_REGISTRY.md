# Harbor registry runbook

This is how the registry gets built and looked after. Harbor runs as containers
from its official offline installer, on Podman or Docker CE, on an existing
RHEL 9 server with no internet access. It holds the platform content the
Supervisor and VKS pull: Supervisor Service bundles, VKS itself, the VKS
add-ons and AKO, whichever each environment turns on. The Harbor Supervisor Service, where workload images go, is a separate
registry, and none of this touches it.

## How the pieces fit

```
Connected workstation (WSL or Linux)    transfer       Each air-gapped environment
------------------------------------    --------       ---------------------------
python3 kit choose --env ..        ->   carried   ->   python3 kit publish --env ..   check and stage (Nexus if it's on)
python3 kit check                       across         python3 kit setup --env ..     settings, certificate, vault
python3 kit fetch                                      python3 kit build --env ..     checks, then builds from the staged files
  Harbor installer + Sigstore check                    python3 kit load --env ..      Broadcom bundles into Harbor
  compose provider, Docker CE if wanted                python3 kit verify --env ..    checks the registry, any time
  Broadcom items the environments turn on (imgpkg), other files
  a copy of this repo, SHA256SUMS
```

`kit.yml` decides what goes into a transfer. Inside, `kit publish` stages the
Harbor files on the control host and the build reads them from there. With
`nexus_enabled: true` they go to the environment's Nexus as well: the installer,
signature, manifest and keys in a raw repo, and the EPEL packages
(podman-compose only) in a yum repo. The Broadcom content goes into
Harbor itself, since the Supervisor and VKS pull from an OCI registry.
What goes in is a menu: `broadcom/catalog.yml` lists the items with every
version's image, and each environment turns items on in
`group_vars/registry/broadcom.yml`. `kit fetch` carries whatever any environment
turns on, and `kit load --env <env>` pushes that environment's into their Harbor
projects and writes copies of the Supervisor Service YAMLs that point at Harbor,
ready to add in vCenter. `broadcom/README.md` covers it.

If you'd rather build the Harbor files with Ansible on a connected RHEL 9 box
instead of `kit fetch`, `stage_harbor_artifacts.yml` does that part
(`roles/stage_harbor_artifacts/README.md`).

Each environment has its own inventory and its own vault. Nothing is shared
between environments.

## Roles

| Role | Runs on | What it does |
|---|---|---|
| `stage_harbor_artifacts` | Connected RHEL box | The Ansible version of `scripts/fetch_harbor.sh`: installer, Sigstore check, podman-compose and python3-dotenv from EPEL, `harbor_artifacts.yml` and `SHA256SUMS` |
| `install_podman_offline` | Registry server | Installs Podman, netavark and aardvark-dns from the server's repos, makes sure Podman is using netavark, and installs the compose provider (podman-compose from Nexus's yum repo, or the docker-compose binary) |
| `install_docker_offline` | Registry server | Installs Docker CE and its compose plugin, from the server's repos or from the RPMs in the transfer |
| `download_harbor_artifacts` | Registry server | Copies the installer from staging (or downloads it from Nexus) and checks its sha256 against the manifest |
| `configure_harbor_tls` | Registry server | Puts the certificate and key you stage in place and trusts their CA; or, on an IdM client, requests the certificate from IdM |
| `install_harbor` | Registry server | Unpacks Harbor, writes `harbor.yml`, runs Harbor's prepare step, adapts the compose file for Podman, and adds the systemd units and certificate sync. It also handles in-place upgrades |
| `configure_harbor_projects` | Registry server | Waits for Harbor to report healthy, then creates `sup-services`, `tanzu-packages` and `tkg`, plus the projects the environment's Broadcom items go to (`vks`, `ako`). `library` comes with Harbor |
| `verify_harbor` | Registry server | Read-only. Fails on a stopped container, an unhealthy component, a missing project or an expired certificate |
| `configure_nexus` | Control host | Creates the kit's repos, roles and accounts in Nexus over its REST API (`configure_nexus.yml`) |

Every role takes `desired_state: present | absent`. `build_registry.yml` puts
Harbor in place. `remove_registry.yml` runs the Harbor roles in reverse with
`absent` and leaves the container runtime installed.

## Where the settings go

`python3 kit setup --env <env>` writes the values that differ from one
environment to the next: the server and how Ansible reaches it, the registry's
name, the data volume, the certificate, Nexus, the Broadcom items and the vault.
Everything else has a working default. The table is for reading, not for
filling in.

| File | What's in it |
|---|---|
| `inventories/<env>/group_vars/all/main.yml` | `install_root`, `stage_root`, `artifact_staging`, `enable_firewall` |
| `inventories/<env>/group_vars/all/environment.yml` | Domain, IdM, vCenter, networks. Facts about the environment, kept in one place |
| `inventories/<env>/group_vars/all/artifacts.yml` | Where the Harbor files come from: `nexus_enabled` (off: the staging folder), and Nexus's URL and repo names when it's on |
| `inventories/<env>/group_vars/all/nexus.yml` | Only for `configure_nexus.yml`: the account names, anonymous access |
| `inventories/<env>/group_vars/registry/main.yml` | Runtime, compose provider, projects, TLS mode, ports, `harbor_data_require_mount` |
| `inventories/<env>/group_vars/registry/harbor_artifacts.yml` | `harbor_version`, `harbor_installer_file`, `harbor_installer_sha256`. `kit publish` writes this one |
| `inventories/<env>/host_vars/<host>.yml` | `registry_server_fqdn`, `harbor_hostname`, `harbor_data_volume` |
| `inventories/<env>/group_vars/all/vault.yml` | Harbor's admin and database passwords and the Nexus read account, written and encrypted by `python3 kit setup`. The Nexus admin and upload accounts too, if you use `configure_nexus.yml` |
| `kit.yml` | What the next transfer carries: Harbor release, compose provider, Docker CE, Broadcom content, other files |
| `inventories/connected/group_vars/all/stage.yml` | The same idea, for `stage_harbor_artifacts.yml` |

## Before the first build

- **The server.** RHEL 9 with Podman, and its BaseOS and AppStream repos
  available through the environment's own mirror. 4 vCPU and 8 GB of memory
  to spare, ports 80 and 443 free.
- **Space for the images.** 160 GB or more at `/data`, big enough for
  everything the Supervisor and VKS will pull, with room to grow. Its own disk
  is best; `harbor_data_require_mount: true` makes the build insist on it.
- **The name.** A DNS record for `harbor_hostname` that the Supervisor, the VKS
  nodes and the control host resolve.
- **The certificate.** A certificate and key for `harbor_hostname` and the CA
  that issued them, in `<artifact_staging>/tls/` on the control host as
  `<harbor_hostname>.crt`, `<harbor_hostname>.key` and `ca.crt`. The build puts
  them in place and makes the server trust the CA; `kit load` uses the same CA.
  `python3 kit setup` asks for the three files, checks them (the name, the
  dates, that the key and the CA belong to the certificate) and stages them.
  On a server enrolled in IdM you can have IdM issue it instead
  (`harbor_tls_mode: ipa`, after `ipa service-add HTTP/<harbor_hostname>`).
- **Nexus, if you want it.** With `nexus_enabled: true`: a raw (hosted) repo, a
  yum (hosted) repo with repodata depth 0, a read account for Ansible and dnf,
  and an upload account for `python3 kit publish`. `configure_nexus.yml` can
  create all of it over Nexus's REST API (`roles/configure_nexus/README.md`).
- **Runtime and compose provider.** On Podman, podman-compose comes from EPEL
  in the transfer. If EPEL isn't allowed, use Docker's compose binary instead:
  `harbor.compose_provider: docker-compose` in `kit.yml` and
  `harbor_podman_compose_provider: docker-compose` in the inventory. On Docker CE
  (`harbor_container_runtime: docker`), Docker comes from the server's own repos,
  or from the transfer with `docker_ce.enabled: true` and
  `docker_offline_source: staged`. `python3 kit publish` warns you when the
  transfer doesn't carry what the inventory expects.
- **The control host.** ansible-core 2.14 or later, nothing else; the
  playbooks only use `ansible.builtin`. Its account logs in to the registry
  server with an SSH key and uses sudo there; if sudo wants a password, the
  kit asks for it once per run. Harbor can also go on the control host itself
  (setup asks). `python3 kit doctor --env <env>` checks all of it. If Ansible runs in a container and
  `artifact_staged_on` is `controller`, mount `artifact_staging` into it.

## After the first build

1. Change the admin password in the Harbor portal, then run
   `python3 kit setup --env <env>` and answer no when it asks to keep the
   vault's passwords: it asks for the new one. The build only sets it the
   first time.
2. If the site has a directory (IdM or AD), point authentication at it over
   LDAP before any local users exist, and leave self-registration off.
3. Load the Broadcom content: `python3 kit load --env <env>` pushes the items
   this environment turns on into their projects, writes the Supervisor Service
   YAMLs that point at Harbor, and says what each item needs next.
4. In vCenter, add the registry under Supervisor > Configure > Container
   Registries, with the CA that issued its certificate (`ca.crt` from
   `<artifact_staging>/tls/`).
5. Make sure the VKS cluster nodes trust that CA too, then pull one image from a
   node to prove it.

## Day 2

- **Upgrading Harbor.** Set `harbor.version` in `kit.yml`, run
  `python3 kit fetch`, carry it in, then `python3 kit publish` and
  `python3 kit build`. `install_harbor` sees the new version and follows
  Harbor's upgrade steps: stop, copy the database, unpack, migrate `harbor.yml`,
  redeploy. Check the release notes for how far you can jump, and try it
  somewhere that doesn't matter first.
- **Certificate renewals.** Run `python3 kit setup --env <env>`, answer no
  when it asks to keep the staged certificate, give it the new files, then
  `python3 kit build --env <env>`. With IdM, certmonger renews in place on its
  own. Either way `harbor-cert-sync.path` copies the new certificate into
  Harbor and restarts `nginx`, and `python3 kit verify --env <env>` tells you
  whether the copy Harbor is serving matches the one on disk.
- **Taking Harbor off.** `python3 kit remove --env <env>` asks first, then
  takes Harbor off and leaves `/data`, `harbor.yml` and the runtime alone. Add
  `--keep-certificate` to keep the certificate too.
- **Switching runtime.** `python3 kit remove --env <env>` first, then set
  `harbor_container_runtime` in `group_vars/registry/main.yml`, then
  `python3 kit build --env <env>`. `install_harbor` won't deploy on a different runtime until
  the remove has run.

- **Trying any of this out.** The lab (`docs/LAB.md`) runs everything on this
  page on one machine, including upgrades and switching runtime.

## Why it's built this way

- **Podman by default.** Harbor's installer only knows Docker, so
  `install_harbor` runs the same steps with Podman. `docs/PODMAN.md` has the
  details and where support stands.
- **No vulnerability scanning.** Trivy needs a vulnerability database, and that
  would have to come across with every update.
- **No backup role.** All the content can be loaded again from the transfer
  with `python3 kit load`.
- **The kit never upgrades the server.** OS packages come from the
  environment's own repos, and only packages the server is missing come from
  the transfer.
