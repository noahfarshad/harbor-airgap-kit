# Changelog

## [1.2.0] - 2026-10-05

Notes:
- The public tree omits `deployments/` and `scripts/package.py`. Those build a site package and do not belong in the shared kit.
- Example hosts are `CHANGE_ME` or `harbor.lab.internal`. No site inventory is included.


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

## [1.1.0] - 2026-10-05

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
<!-- [lab] -->
- `lab\windows\Start-HarborLab.ps1` starts the lab and keeps it running, since
  WSL stops an idle distribution after about 15 seconds.
<!-- [/lab] -->

## [1.0.0] - 2026-10-03

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
<!-- [lab] -->
- The lab: the whole pipeline on one machine (Windows 11 with WSL, or a RHEL 9
  VM), with its own Nexus and CA, on Podman or Docker CE. See `docs/LAB.md`.
<!-- [/lab] -->
