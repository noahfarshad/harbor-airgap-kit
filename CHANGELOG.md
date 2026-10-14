# Changelog

## 1.4.1 (2026-10-14)

Notes on the public tree:
- It omits `deployments/` and `scripts/package.py`. They build a package for one
  place I deliver to, and don't belong in the shared kit.
- `inventories/dev` is the filled example, with `example.coach` names and
  documentation addresses, in the 1.4.1 inventory format. It replaces
  `inventories/example` from the 1.2.0 public tree.

- The certificate check takes the registry's name only from the certificate's
  Subject Alternative Name, and says so plainly when it's handed a CA's
  certificate, or one without a DNS name in it. Before, a CA certificate's name
  constraints could be listed as the names it was for.

## 1.4.0 (2026-10-09)

Inside an environment, everything is `python3 kit`: no `make`, no `sed`, no editor.

- `python3 kit setup --env <env>` asks for what differs from one environment
  to the next, one thing at a time: whether Harbor goes on this machine, or
  which server and account; the registry's DNS name; the data volume; the
  certificate (from IdM, or files from any CA); Nexus; the Broadcom items; the
  passwords. It checks each answer (the server resolves, the certificate is for
  the registry's name, in date, matches its key and was issued by the CA), lists
  every change, and saves only on a yes, keeping each file's comments. It stages
  the certificate, writes the vault encrypted, and starts a new environment from
  `inventories/_template`. Run it again to change anything; Enter keeps what's
  there. After Harbor's admin password changes in the portal, it puts the new
  one in the vault, encrypted with the same vault password.
- `python3 kit build`, `verify` and `remove --env <env>` check what would stop
  the playbook before starting it: ansible-core 2.14 or later, the registry's
  label and its `host_vars` file, placeholders, the SSH login and sudo on the
  server (or Harbor on this machine with `ansible_connection: local`), the
  vault, the staged Harbor files and the certificate. Each problem comes with
  its fix in one sentence. They ask for the vault password, and for the sudo
  password when sudo needs one. `python3 kit doctor --env <env>` runs the checks
  on their own.
- `python3 kit remove` asks before it starts. `--keep-certificate` leaves the
  certificate on the server, and `--purge-data` asks you to type the
  environment's name.
- `python3 kit choose --env <env>`, on the connected workstation, picks what an
  environment gets from the Broadcom catalog before a fetch. Setup warns when
  the staged transfer doesn't carry an item the environment turns on.
- `python3 kit` runs the playbooks with the repository's `ansible.cfg`, even
  from a world-writable folder such as `/mnt/c` under WSL, where Ansible skips it,
  and with the repository's own Ansible in `.venv` when there is one (the lab's),
  as `make` does.
- The staged certificate, key and CA are read from `harbor_tls_staged_cert`,
  `_key` and `_ca` when an inventory sets them, not only from
  `<artifact_staging>/tls/`.
- `connected` isn't listed as an environment any more; it only holds the
  settings for `stage_harbor_artifacts.yml`.
- The docs, the inventory comments and the playbooks' messages give the
  `python3 kit` commands. `make` stays for the lab, `make lint`, `make syntax`
  and packaging, and `make lab-run` builds and verifies through the kit, the
  way an environment does.

## 1.3.1 (2026-10-09)

The catalog refresh decides nothing on its own.

- `python3 kit catalog --refresh` asks yes or no before each change, with the
  recommended answer as the default: a newer patch becomes the default unless
  you say no, a newer line doesn't unless you say yes, an environment's pin
  moves only on a yes, and a version Broadcom has deleted comes out only if
  nothing uses it. `--yes` takes the recommended answers for unattended runs,
  and `--dry-run` only shows what it would ask. Outside a terminal, without
  `--yes`, it changes nothing. `--write` from 1.3.0 still works, as `--yes`.
- Saying no to a newer default records a `hold` on the item, with the reason,
  who and when. Later runs show it and recommend keeping it until someone says
  yes to a newer version.
- "Gone" means the registry answered 404, never a timeout. A new version goes
  in only once its image answers. The catalog before a change is kept as
  `broadcom/catalog.yml.previous`.
- A version or an item listed twice in `broadcom/catalog.yml` now stops every
  command; YAML would otherwise keep the last one without a word.
- `kit check` and `kit fetch` warn when the catalog hasn't been checked in 90
  days.
- The lab's end-to-end run is `make lab-run`, from `lab/run.sh`, and
  `New-HarborLab.ps1 -RunPipeline` starts it. The old names are gone.

## 1.3.0 (2026-10-09)

Keeping the catalog current, and the fixes from the first working session inside.

- `python3 kit catalog --refresh` asks Broadcom's registry, without a login,
  whether every catalog reference still answers, what's newer, and what the
  catalog doesn't cover yet. `--write` adds the new versions and moves a default
  only to a newer patch of the same line, keeping every comment in the file.
  `broadcom/README.md` has the rules.
- The catalog is current as of today: the Consumption Interface 9.1.3 and VKS
  3.7.2 are in, and they're the defaults for those two items.
- `kit check` and `kit fetch` warn about a Supervisor Service an environment
  turns on that has no YAML in `broadcom/services/` yet, so it's downloaded
  before the transfer is built rather than discovered inside.
- `kit publish` warns when the repository it runs from is older than the copy
  the transfer carries, and prints how to update it.
- The build stops up front, with the fix in the message, when the registry's
  label in `hosts` no longer matches its `host_vars` file, and when the registry
  is the machine Ansible runs on but `ansible_connection: local` isn't set.
- The `hosts` and `host_vars` files say plainly that the name under
  `[registry]` is a label, not the server's name.
- The lab setup stops saying it installs Ansible collections; there are none to install.

## 1.2.0 (2026-10-05)

Fewer things an environment has to have.

- No collections. The two modules that needed `ansible.posix` and
  `community.general` are plain `firewall-cmd` and `semanage` commands now, so a
  bare ansible-core (2.14 or later, RHEL 9's) runs every playbook.
- No IdM. The certificate defaults to one you stage, from any CA, in
  `<artifact_staging>/tls/` with that CA. The build makes the server trust the CA
  and `kit load` uses it. IdM issuing it is still there as `harbor_tls_mode: ipa`.
  The staged files moved out of the Harbor files' folder, which each publish
  replaces.
- Nexus is optional: `nexus_enabled` in `group_vars/all/artifacts.yml` turns it
  on or off, and it's off in the template. Off, the build reads the Harbor files
  from the staging folder on the control host.
- A separate data disk is recommended, not enforced (`harbor_data_require_mount:
  false` in the template). The README lists what a registry server needs.

## 1.1.0 (2026-10-05)

- `broadcom/catalog.yml`: Supervisor Services (Argo CD, Contour, ExternalDNS,
  Velero, Consumption Interface, CA Cluster Issuer, Harbor, Secret Store, DSM,
  the management proxies), VKS itself, the VKS add-ons repository and AKO, with
  every version's image. Each environment turns items on in
  `group_vars/registry/broadcom.yml`.
- `kit fetch` carries what the environments turn on, `kit load --env` pushes
  only that environment's, and `make build-registry` creates the projects they
  go to. `python3 kit catalog` shows the list and who has what on.
- `broadcom.services_dir` is read from the repository, so the lab picks up
  YAMLs in `broadcom/services/` too.
- Publishing or fetching again keeps one previous copy of the staged files or
  the transfer, not every one.
- `lab\windows\Start-HarborLab.ps1` starts the lab and keeps it running, since
  WSL stops an idle distribution after about 15 seconds.

## 1.0.0 (2026-10-03)

First release.

- `python3 kit` builds a transfer from `kit.yml` on a connected workstation:
  Harbor's offline installer (checked against its Sigstore signature), the
  compose provider, Docker CE if you want it, Broadcom bundles, any other files
  you list, a copy of this repo, and one SHA256SUMS over all of it. Inside,
  `kit publish` checks it and uploads the Harbor files to Nexus, and `kit load`
  pushes the Broadcom bundles into Harbor.
- Ansible roles build Harbor on RHEL 9, on Podman or Docker CE, with a
  certificate from IdM or one you stage, systemd units, certificate renewals
  carried into Harbor, the Harbor projects, and in-place upgrades.
  `verify_registry.yml` checks it and `remove_registry.yml` takes it off again.
- `make configure-nexus` sets up the Nexus repos, roles and accounts the kit
  uses, over Nexus's REST API.
- `inventories/_template/` to start a new environment from.
- The lab: the whole pipeline on one machine (Windows 11 with WSL, or a RHEL 9
  VM), with its own Nexus and CA, on Podman or Docker CE. See `docs/LAB.md`.
