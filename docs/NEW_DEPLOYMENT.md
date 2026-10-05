# Setting up a new deployment

Everything in this repo is generic. Whatever is specific to one place I'm
delivering to lives in its own folder under `deployments/`: its inventories, its
`kit.yml`, any docs only it needs, and a `deployment.yml` that names the
package. `make package DEPLOYMENT=<name>` puts the repo and that folder together
into the zip I hand over, and stops if another deployment's name shows up in it.

```
deployments/acme/
    deployment.yml        package: acme-harbor     keep_lab: false
    kit.yml               what their transfers carry
    inventories/
        prod/             one directory per environment, copied from inventories/_template
        test/
    docs/                 anything only they need, like a variables page or open questions
    README.md             optional, replaces the generic README in their package
    CHANGELOG.md          optional, their own release history
```

## 1. Create the folder

```bash
mkdir -p deployments/acme/inventories deployments/acme/docs
cp -r inventories/_template deployments/acme/inventories/prod
cp kit.yml deployments/acme/kit.yml
printf 'package: acme-harbor\nkeep_lab: false\n' > deployments/acme/deployment.yml
```

Then add a line for it to `deployments/README.md`.

`keep_lab: true` sends the lab along too, in case they want to rehearse on a
Windows 11 desktop (WSL 2.4.4 or newer) or a RHEL 9 VM with internet access. I
leave it off when the lab is only for my own testing.

## 2. Fill in each environment

`grep -rn CHANGE_ME deployments/acme/inventories/prod` lists every value that
still needs setting. Roughly:

- `hosts`: the registry server's name in the inventory. Rename
  `host_vars/registry01.yml` to match.
- `host_vars/<host>.yml`: `registry_server_fqdn`, `harbor_hostname` (the
  registry's own DNS name) and `harbor_data_volume`.
- `group_vars/all/artifacts.yml`: leave `nexus_enabled: false` unless they want
  the Harbor files kept in their Nexus; then `nexus_url` and the repo names.
- `group_vars/all/environment.yml`: domain, IdM, vCenter, networks. The registry
  roles don't read these, but it's handy to have them in one place.
- `group_vars/registry/main.yml`: the compose provider, the certificate (one
  they hand you, `staged`, unless the server is an IdM client and they'd rather
  IdM issued it), and the Harbor projects.
- `group_vars/all/nexus.yml`: only matters if you'll run `make configure-nexus`.
- `group_vars/all/vault.yml.example`: the secrets their `vault.yml` needs. They
  create and encrypt that file themselves, inside.

Anything that's the same across all of their environments goes in `group_vars`.
Anything for a single server goes in `host_vars`.

## 3. Their kit.yml

Set the Harbor release and the compose provider, turn on Docker CE if their
registry server runs Docker and can't get it any other way. The Broadcom content
each environment gets is in its inventory, `group_vars/registry/broadcom.yml`
(copied from the template with everything off), and `broadcom.environments` in
`kit.yml` says which environments the transfer carries content for.

The compose provider in `kit.yml` has to match `harbor_podman_compose_provider`
in their inventories, and `docker_ce.enabled` has to go with
`docker_offline_source: staged`. `python3 kit publish` warns you if they don't.

## 4. Their Nexus, only if they want to use it

With `nexus_enabled: true`, `make configure-nexus ENV=prod` creates the repos, roles and accounts the kit
needs over Nexus's REST API, as long as their Nexus admin password is in the
vault (see `roles/configure_nexus/README.md`). Their Nexus admin can also do it
by hand: a raw (hosted) repo, a yum (hosted) repo with repodata depth 0, a read
account and an upload account.

## 5. Rehearse it in the lab

Copy their `group_vars/registry/main.yml` choices into `inventories/lab/`,
keeping the lab's certificate, data disk and SELinux lines, and run
`make lab-demo` (with `RUNTIME=docker` if they run Docker CE). Put the lab's file
back afterwards.

## 6. Build the package

```bash
make package DEPLOYMENT=acme          # dist/acme-harbor-<version>.zip, plus dist/acme-harbor/ to look through
cd dist/acme-harbor && make syntax    # every playbook against each of their inventories
```

Some things never go in a package: `deployments/` itself, `scripts/package.py`
and this page. Without the lab it also leaves out `lab/`, `inventories/lab`,
`kits/lab.yml`, the lab playbooks and roles, and `docs/LAB.md`.

In Markdown files, the Makefile and `.gitignore`, anything between `[internal]`
markers is dropped from every package, and anything between `[lab]` markers is
dropped when the lab isn't going. Each marker has to sit on its own line.

Vaults, `.vault_pass`, the lab's runtime file, `.venv/`, `collections/` and
`dist/` never go in either. Their vaults get created inside their environments
and stay there.
