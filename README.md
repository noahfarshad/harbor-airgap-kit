# harbor-airgap-kit

I built this to stand up a containerized Harbor registry inside air-gapped
vSphere environments, so the Supervisor and VKS have a registry they can pull
from without internet access. Doing it by hand means a lot of downloads,
checksums and copied commands, and every one of those is a chance to get
something wrong. This turns it into a handful of commands plus Ansible. It's
meant to work for anyone delivering Harbor into a disconnected environment,
not just me.

License: GPL-3.0. The write-up is on essential.coach:
[Air-Gapped VKS on VCF 9](https://essential.coach/air-gapped-vks-on-vcf-9/).

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
   Nexus, if you turn that on). `python3 kit setup` asks a few questions and
   writes the environment's settings, certificate and vault for you.
   `python3 kit build` checks everything, then builds Harbor on a RHEL 9 server
   from there, on Podman, and `python3 kit load` pushes that environment's
   Broadcom content into it.

The Broadcom content is a menu in `broadcom/catalog.yml`: Supervisor Services
(Argo CD, Contour, ExternalDNS, Velero and the rest), VKS itself, the VKS
add-ons repository and AKO, with every version's image. Each environment turns
items on or off in `group_vars/registry/broadcom.yml`. `broadcom/README.md` has
the details.

The one thing it doesn't do is the vCenter side: adding the registry to the
Supervisor and getting VKS to trust its CA. That's two screens, and the
runbook covers them.

## Try it on your own machine first

The lab runs the whole thing on one machine, with the same commands you'd use
in a real environment, plus its own Nexus and its own CA. I use it to try out
changes before they go anywhere near a real environment. On Windows 11, from
this folder in PowerShell (no admin needed):

```powershell
PowerShell -ExecutionPolicy Bypass -File .\lab\windows\New-HarborLab.ps1 -RunPipeline
```

That sets up a separate WSL distribution called `harbor-lab` and runs
everything in it. Add `-Runtime docker` to put Harbor on Docker CE instead of
Podman. On an AlmaLinux, Rocky or RHEL 9 VM, run this as root from this folder:

```bash
bash lab/bootstrap.sh && make lab-run
```

`docs/LAB.md` has the rest.

## Using it in an environment

```bash
# On the connected workstation, from this folder
python3 kit catalog --refresh   # anything newer from Broadcom? asks yes or no before changing broadcom/catalog.yml
python3 kit check     # is kit.yml right, and can everything be reached?
python3 kit fetch     # builds ~/kit-transfer/<name>, plus a copy in C:\Users\<you>\kit-transfer under WSL

# Inside, on the Ansible control host, once the transfer is across
python3 kit publish --from <transfer> --env <env>   # check the transfer and stage it
python3 kit setup   --env <env>   # questions; writes the settings, stages the certificate, makes the vault
python3 kit build   --env <env>   # checks everything first, then builds or updates Harbor
python3 kit load    --env <env>   # the Broadcom content that environment turns on
python3 kit verify  --env <env>   # check it any time
```

Every transfer has a `TRANSFER.txt` that lists what's in it along with these
same commands. There's no default environment, so you always pass `--env` and
can't hit the wrong one by accident. Nothing inside needs `make`, `sed` or an
editor: `setup` asks, checks each answer (the server answers, the certificate
is for the registry's name and matches its key and CA), shows what it will
change and saves only on a yes. Run it again to change anything. Before every
run, `build`, `verify` and `remove` check what would stop the playbook (Ansible,
the login and sudo on the server, the vault, the staged files, the certificate)
and stop with the fix in one sentence. `python3 kit doctor --env <env>` runs
those checks on their own, and `python3 kit --help` lists every command.

`docs/HARBOR_REGISTRY.md` is the runbook: what to have ready before the first
build, what to do after it, and day-2 work like upgrades and certificate
renewals.

## A new environment

```bash
python3 kit setup --env <env>
```

For a name that isn't under `inventories/` yet, it offers to start one from
`inventories/_template`, then asks the same questions. The build won't start
while any `CHANGE_ME` is left, and `python3 kit doctor --env <env>` names any
that are.

`inventories/dev` is a filled example with `example.coach` names: the registry
is `registry.example.coach` on `registry01.example.coach`, on Podman, with Nexus
off and a staged certificate. It shows what a finished environment looks like.
For your own, let `python3 kit setup` start from `inventories/_template`.

## What's where

```
kit, kit.yml                the one tool you run, and what goes into a transfer
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

And for the lab:

```
inventories/lab/            one machine plays every part
lab_up.yml, lab_down.yml    the lab's own CA and Nexus
kits/lab.yml                the lab's kit.yml
lab/                        bootstrap, the end-to-end run, and the Windows scripts (docs/LAB.md)
```

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
  the control host; `python3 kit setup` checks them and puts them there. If the
  server happens to be enrolled in IdM, IdM can issue it instead (setup asks),
  but nothing needs IdM.

**The Ansible control host:** ansible-core 2.14 or later, which is what RHEL 9
ships. The playbooks only use `ansible.builtin`, so there are no collections to
bring in. It logs in to the registry server with an SSH key, as an account
that can use sudo there; if sudo asks for a password, the kit asks for it once
per run. Harbor can also go on the control host itself. `python3 kit doctor`
checks all of it.

**The connected workstation:** python3 (3.6 or later), bash and curl, on WSL or
Linux, able to reach GitHub, projects.packages.broadcom.com and the storage it
hands downloads to (jfrog-prod-usw2-shared-oregon-main.s3.amazonaws.com).

**Nexus is optional.** Set `nexus_enabled: true` in an environment's
`group_vars/all/artifacts.yml` and `kit publish` uploads the Harbor files to its
Nexus, and the build reads them from there. Leave it off and the build reads
them from the staging folder on the control host.

Noah Farshad
