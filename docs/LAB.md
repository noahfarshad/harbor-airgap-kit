# The lab

The lab is how I test this without a real environment. It runs the whole
pipeline on one machine with the same commands you'd use for real: build a
transfer, publish it to Nexus, build Harbor, load the Broadcom bundles, verify.
It brings its own Nexus (in Podman) and its own CA, which are the two things a
real environment would normally give you.

The only part it can't do is the vCenter side, adding the registry to the
Supervisor and having VKS trust its CA. Those steps are in `HARBOR_REGISTRY.md`
under "After the first build".

## What you need

- Windows 11 with WSL 2.4.4 or newer (check with `wsl --version`), or an
  AlmaLinux, Rocky or RHEL 9 VM.
- About 6 GB of free memory for the lab. Nexus and Harbor take about 2 GB each,
  and WSL gets half your RAM by default, which is usually plenty.
- About 25 GB of disk.
- Internet access to GitHub, Docker Hub, dl.fedoraproject.org,
  download.docker.com, projects.packages.broadcom.com, PyPI, Ansible Galaxy and
  the AlmaLinux mirrors.
- No accounts. The Broadcom bundles download anonymously. You'd only need a
  Broadcom login to grab Supervisor Service YAMLs from support.broadcom.com in a
  browser.

The lab's Nexus is Sonatype's free Community Edition, and `make lab-up` accepts
its license agreement for you (`nexus_accept_eula` in
`inventories/lab/group_vars/all/nexus.yml`).

## On Windows 11

From this folder, in PowerShell (no admin needed):

```powershell
PowerShell -ExecutionPolicy Bypass -File .\lab\windows\New-HarborLab.ps1 -Demo
```

Here's what that does:

1. Installs a separate WSL distribution called `harbor-lab` in
   `%LOCALAPPDATA%\harbor-lab`. It's AlmaLinux 9, which is free and close enough
   to RHEL 9. Your other distributions aren't touched.
2. Turns on systemd, makes root the default user, and stops WSL from rewriting
   `/etc/hosts`.
3. Copies this folder to `/opt/harbor-airgap-kit` inside it.
4. Runs `lab/bootstrap.sh`, which installs Python 3.12, Podman and a few tools,
   puts ansible-core 2.21 and the collections in `.venv`, and runs `make lab-up`
   (vault, CA, Nexus, and Nexus's repos and accounts).
5. With `-Demo`, runs `make lab-demo` (below). Add `-Runtime docker` to build
   Harbor on Docker CE instead of Podman.

The first run takes 15 to 20 minutes, mostly downloads. Run the script again
whenever you change something here. It copies the folder back in and keeps the
lab's vault, its runtime and the last publish. `-Recreate` throws the
distribution away and starts over.

After that:

```powershell
wsl -d harbor-lab                                                        # root shell in the lab
wsl -d harbor-lab -- make -C /opt/harbor-airgap-kit lab-demo
wsl -d harbor-lab -- make -C /opt/harbor-airgap-kit lab-demo RUNTIME=docker
wsl -d harbor-lab -- make -C /opt/harbor-airgap-kit lab-info
```

WSL normally stops a distribution about 15 seconds after the last command
attached to it finishes, even with services running, and Harbor and Nexus would
stop with it. So the script ends by starting a hidden `sleep infinity` in the
lab, which keeps it up until you stop it with `wsl --terminate harbor-lab`.
After a reboot or a `wsl --shutdown`, start it again (Harbor and Nexus come up on
their own; give them a minute or two):

```powershell
PowerShell -ExecutionPolicy Bypass -File .\lab\windows\Start-HarborLab.ps1
```

To use Harbor from your Windows browser, add `127.0.0.1 harbor.lab.internal` to
`C:\Windows\System32\drivers\etc\hosts` (that part needs admin), then trust the
lab's CA for your account. No admin for this one; Windows just asks you to
confirm:

```powershell
Import-Certificate -FilePath \\wsl.localhost\harbor-lab\etc\harbor-lab\pki\ca.crt -CertStoreLocation Cert:\CurrentUser\Root
```

Then go to https://harbor.lab.internal. Nexus is at http://localhost:8081.
`make lab-info` prints both steps and the logins. The CA can only sign
certificates for the lab's own names, so trusting it doesn't trust anything
else.

To get rid of it, run
`PowerShell -ExecutionPolicy Bypass -File .\lab\windows\Remove-HarborLab.ps1`.
That deletes the distribution and everything in it. If you imported the CA,
remove that too: `certmgr.msc`, Trusted Root Certification Authorities,
"harbor-airgap-kit lab CA".

## On a VM

On AlmaLinux, Rocky or RHEL 9, as root, from this folder:

```bash
bash lab/bootstrap.sh
make lab-demo                  # or: make lab-demo RUNTIME=docker
```

## What lab-demo does

1. `python3 kit --config kits/lab.yml check`, then `fetch`. Checks every
   source, verifies Harbor's Sigstore signature and the checksums for
   docker-compose and the Docker CE RPMs, downloads the Broadcom items the lab
   turns on with imgpkg, and writes the transfer.
2. `python3 kit publish --from /var/tmp/kit-transfer/lab-harbor-2.15.2 --env lab`.
   Checks the transfer again, makes sure it has what the inventory expects,
   stages it, and uploads the Harbor files to Nexus with the upload account.
3. `make build-registry ENV=lab`. Builds Harbor from Nexus with the read
   account: runtime, installer, certificate, systemd units, projects, checks.
4. `python3 kit load --env lab`. Pushes the lab's Broadcom items into their
   Harbor projects over TLS, trusting the lab CA.
5. `make verify-registry ENV=lab`. Every container running, Harbor healthy, the
   projects there, the certificate valid.

`RUNTIME=docker` first takes Harbor off Podman (keeping its data), then runs the
same five steps with Harbor on Docker CE, installed from the RPMs in the
transfer. `RUNTIME=podman` moves it back. Run `make build-registry ENV=lab` a
second time on either one and it should report no changes.

## Making it look like a real environment

- More or less Broadcom content: turn items on or off in
  `inventories/lab/group_vars/registry/broadcom.yml` (it starts with Argo CD,
  Contour and AKO) and run `make lab-demo` again. `python3 kit catalog` lists
  what's there.
- podman-compose instead of docker-compose: set `compose_provider:
  podman-compose` in `kits/lab.yml` and `harbor_podman_compose_provider:
  podman-compose` in `inventories/lab/group_vars/registry/main.yml`. Nexus's
  yum repo then serves the EPEL packages.
- A different Harbor release: change `harbor.version` in `kits/lab.yml` and run
  `make lab-demo`. `install_harbor` follows Harbor's own upgrade steps.
- A real environment's settings: copy the choices from its
  `group_vars/registry/main.yml` into `inventories/lab/`, keeping the lab's
  certificate, data disk and SELinux lines, and run `make lab-demo`.

## Day to day

```
make lab-up                       build or fix the lab's CA and Nexus; safe to rerun
make lab-demo [RUNTIME=docker]    the whole pipeline
make lab-info                     URLs, the runtime, and the logins
make lab-down                     take Harbor down and stop Nexus, keeping the data
make lab-destroy                  everything: Harbor and Nexus data, CA, vault, transfers
```

## When something goes wrong

- **`wsl --install` can't find AlmaLinux-9.** Run `wsl --update`, then
  `wsl --list --online` to see what's offered, and pass a different one with
  `-Distribution`.
- **"systemd is not running".** Run `wsl --terminate harbor-lab`, then the
  script again.
- **Pulling the Nexus image fails with a 429.** That's Docker Hub's rate limit.
  Set `lab_nexus_image: mirror.gcr.io/sonatype/nexus3:3.96.4` in
  `inventories/lab/group_vars/all/main.yml` and run `make lab-up`.
- **Nexus never comes up.** Look at `systemctl status nexus` and
  `podman logs nexus` in the lab. It's usually memory: give WSL more in
  `%UserProfile%\.wslconfig` (`memory=12GB` under `[wsl2]`).
- **Downloads fail with certificate errors.** You're probably behind a proxy
  that inspects HTTPS. Put its root CA in `/etc/pki/ca-trust/source/anchors/`
  inside the lab and run `update-ca-trust`.
- **The browser says harbor.lab.internal refused to connect.** The lab has
  probably stopped (`wsl --list --running` won't list it). Start it with
  `lab\windows\Start-HarborLab.ps1`, wait for it to say Harbor answers, and reload.
- **The Windows browser still can't reach Harbor.** Inside the lab,
  `curl -s https://harbor.lab.internal/api/v2.0/ping` should print `Pong`. If it
  does, Windows isn't forwarding to WSL. Make sure `localhostForwarding` isn't
  set to `false` in `.wslconfig`, or put the lab's own address
  (`wsl -d harbor-lab hostname -I`) in the hosts file instead of 127.0.0.1.
- **`make lab-demo` stops partway.** Fix whatever that step complains about and
  run it again. Every step can be rerun.
