# harbor-airgap-kit

Stand up a containerized Harbor registry inside an air-gapped vSphere environment, so the Supervisor and VKS can pull without internet access. One transfer folder, one inventory, three settings.

License: GPL-3.0. Built and proved out for [essential.coach](https://essential.coach).
Full write-up: [Air-Gapped VKS on VCF 9: How the Kit Actually Arrives](https://essential.coach/air-gapped-vks-on-vcf-9/).

Here's the flow:

1. On a connected workstation (WSL on Windows, or any Linux box),
   `python3 kit fetch` downloads Harbor's offline installer and checks its
   signature, gets whatever the registry server will need (a compose provider,
   and Docker CE if you want it), pulls the Broadcom content your environments
   turn on, and writes all of it into one folder with a SHA256SUMS file.
   That folder is the transfer.
2. You carry the transfer across the air gap the way your site does it.
3. Inside, `python3 kit publish` checks the transfer and stages the Harbor
   files on the Ansible control host (or uploads them to the environment's
   Nexus, if you turn that on). `make build-registry` builds Harbor on a RHEL 9
   server from there, on Podman, and `python3 kit load` pushes that
   environment's Broadcom content into it.

The Broadcom content is a menu in `broadcom/catalog.yml`: Supervisor Services
(Argo CD, Contour, ExternalDNS, Velero and the rest), VKS itself, the VKS
add-ons repository and AKO, with every version's image. Each environment turns
items on or off in `group_vars/registry/broadcom.yml`. `broadcom/README.md` has
the details.

The one thing it doesn't do is the vCenter side: adding the registry to the
Supervisor and getting VKS to trust its CA. That's two screens, and the
runbook covers them.

<!-- [lab] -->
## Try it on your own machine first

The lab runs the whole thing on one machine, with the same commands you'd use
in a real environment, plus its own Nexus and its own CA. I use it to try out
changes before they go anywhere near a real environment. On Windows 11, from
this folder in PowerShell (no admin needed):

```powershell
PowerShell -ExecutionPolicy Bypass -File .\lab\windows\New-HarborLab.ps1 -Demo
```

That sets up a separate WSL distribution called `harbor-lab` and runs
everything in it. Add `-Runtime docker` to put Harbor on Docker CE instead of
Podman. Switch later with:

```powershell
wsl -d harbor-lab -- make -C /opt/harbor-airgap-kit lab-demo RUNTIME=docker
wsl -d harbor-lab -- make -C /opt/harbor-airgap-kit lab-demo RUNTIME=podman
wsl --terminate harbor-lab
```

On a VM, the same switch is `make lab-demo RUNTIME=docker` or `RUNTIME=podman`.
`docs/LAB.md` has the certificate import and the rest. On an AlmaLinux, Rocky or RHEL 9 VM, run this as root from this folder:

```bash
bash lab/bootstrap.sh && make lab-demo
```

`docs/LAB.md` has the rest.

<!-- [/lab] -->
## Using it in an environment

```bash
# On the connected workstation, from this folder
python3 kit check     # is kit.yml right, and can everything be reached?
python3 kit fetch     # builds ~/kit-transfer/<name>, plus a copy in C:\Users\<you>\kit-transfer under WSL

# Inside, on the Ansible control host, once the transfer is across
python3 kit publish --from <transfer> --env <env>
make build-registry  ENV=<env>
python3 kit load --env <env>
make verify-registry ENV=<env>
```

Every transfer has a `TRANSFER.txt` that lists what's in it along with these
same commands. There's no default inventory, so you always pass `ENV` and
can't hit the wrong environment by accident. `make help` shows everything else.

`docs/HARBOR_REGISTRY.md` is the runbook: what to have ready before the first
build, what to do after it, and day-2 work like upgrades and certificate
renewals.

## A new environment

`inventories/dev` is filled as `registry.example.coach`:
`registry01.example.coach`, Nexus off, a staged certificate, Podman, and a few
Broadcom items turned on. Copy that directory, or the blank template, and
replace `example.coach`. The build will not start while a `CHANGE_ME` is left.
Create the vault:

```bash
cp -r inventories/_template inventories/<env>
grep -rn CHANGE_ME inventories/<env>
cp inventories/<env>/group_vars/all/vault.yml.example inventories/<env>/group_vars/all/vault.yml
make encrypt-vault ENV=<env>     # once the passwords are in
```

## What's where

```
kit, kit.yml                the transfer tool, and what goes into a transfer
build_registry.yml          builds Harbor: runtime, installer, certificate, projects, checks
verify_registry.yml         read-only checks
remove_registry.yml         takes Harbor off a server (the data stays)
configure_nexus.yml         sets up the kit's Nexus repos and accounts over Nexus's REST API
stage_harbor_artifacts.yml  just the Harbor files, with Ansible on a connected RHEL box
roles/                      one role per job, each with desired_state present | absent
inventories/<env>/          one directory per environment
inventories/dev/            filled example, registry.example.coach
inventories/_template/      start a new environment from this
inventories/connected/      settings for stage_harbor_artifacts.yml
broadcom/catalog.yml        the Broadcom content each environment can turn on
broadcom/services/          Supervisor Service YAMLs from Broadcom; kit load repoints them at Harbor
scripts/                    what kit runs under the hood: fetch, pull, publish
docs/                       the runbook (HARBOR_REGISTRY.md), PODMAN.md, ADDING_A_ROLE.md
```

<!-- [lab] -->
And for the lab:

```
inventories/lab/            one machine plays every part
lab_up.yml, lab_down.yml    the lab's own CA and Nexus
kits/lab.yml                the lab's kit.yml
lab/                        bootstrap, the demo, and the Windows scripts (docs/LAB.md)
```

<!-- [/lab] -->
Variables go from lowest to highest priority: role `defaults/`,
`group_vars/all/`, `group_vars/<group>/`, then `host_vars/<host>.yml`.

## Rules I've stuck to

- Each role has a present side and an absent side (`tasks/is_present.yml` and
  `tasks/is_absent.yml`), picked by `desired_state`. Running anything a second
  time should change nothing.
- Nothing gets downloaded inside an environment. Everything comes in through a
  transfer and gets checked against its SHA256SUMS. Harbor's installer is
  checked against its Sigstore signature before it leaves the connected side,
  and RPMs are checked against their signing keys when they're installed.
- The kit never upgrades a server. OS packages come from the environment's own
  repos, and only packages a server doesn't have yet come from the transfer.
- Passwords live in each environment's `group_vars/all/vault.yml`, encrypted
  with ansible-vault. They never travel in a transfer or a package.
- `make lint` and `make syntax` pass before anything goes out.

## What you need

**The registry server**, one per environment:

- RHEL 9 (or Rocky or Alma 9) with Podman. Docker CE works too, which is handy
  for trying a build on a connected machine first.
- 4 vCPU and 8 GB of memory.
- 160 GB or more for the images, at `harbor_data_volume` (`/data`), ideally on
  its own disk. Size it from what you'll load: a Supervisor Service is anywhere
  from tens of MB to over a GB, and you'll keep a few releases of each.
  `harbor_data_require_mount: true` makes the build insist on a separate disk.
- Ports 80 and 443 free, and 443 reachable from the Supervisor's management
  network and the VKS clusters' networks.
- A DNS name for the registry (`harbor_hostname`) that the Supervisor, the VKS
  nodes and the control host can resolve. It's the name on the certificate, so
  keep it separate from the server's own name and the registry can move later.
- A certificate and key for that name, and the CA that issued them, from any CA
  the Supervisor and VKS will trust. They go in `<artifact_staging>/tls/` on
  the control host. If the server happens to be enrolled in IdM, IdM can issue
  it instead (`harbor_tls_mode: ipa`), but nothing needs IdM.

**The Ansible control host:** ansible-core 2.14 or later, which is what RHEL 9
ships. The playbooks only use `ansible.builtin`, so there are no collections to
bring in. It logs in to the registry server with an account that has sudo
without a password prompt (NOPASSWD).

**The connected workstation:** python3 (3.6 or later), bash and curl, on WSL or
Linux, able to reach GitHub, projects.packages.broadcom.com and the storage it
hands downloads to (jfrog-prod-usw2-shared-oregon-main.s3.amazonaws.com).

**Nexus is optional.** Set `nexus_enabled: true` in an environment's
`group_vars/all/artifacts.yml` and `kit publish` uploads the Harbor files to its
Nexus, and the build reads them from there. Leave it off and the build reads
them from the staging folder on the control host.

