#!/usr/bin/env bash
# lab/bootstrap.sh - turn this machine into the harbor-airgap-kit lab, then
# build the lab's infrastructure (make lab-up). Run as root on AlmaLinux, Rocky
# or RHEL 9 with systemd running: the harbor-lab WSL distribution that
# lab/windows/New-HarborLab.ps1 creates, or a VM. Safe to run again.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Lab names never go through a proxy, if this machine has one.
export no_proxy="${no_proxy:+$no_proxy,}localhost,127.0.0.1,.lab.internal" NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost,127.0.0.1,.lab.internal"

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run this as root (the WSL lab signs in as root)"
# shellcheck source=/dev/null
. /etc/os-release
[[ " ${ID:-} ${ID_LIKE:-} " =~ \ (rhel|centos|fedora)\  && "${VERSION_ID%%.*}" == 9 ]] \
  || die "the lab needs AlmaLinux, Rocky or RHEL 9; this is ${PRETTY_NAME:-unknown}"
[[ "$(cat /proc/1/comm)" == systemd ]] \
  || die "systemd is not running. Under WSL: [boot] systemd=true in /etc/wsl.conf, then wsl --terminate <distribution>"

log "Installing packages (Python 3.12, Podman and tools)"
dnf -y -q install python3.12 python3.12-pip podman python3-pyyaml git make tar unzip openssl zstd jq \
  findutils procps-ng
command -v curl >/dev/null || dnf -y -q install curl-minimal     # the images ship curl-minimal, which conflicts with curl

cd "$REPO"
# A copy from a Windows folder or share arrives writable by everyone, and Ansible
# then ignores ansible.cfg. Taking group and world write away fixes that.
chmod -R go-w "$REPO"

log "Installing ansible-core into $REPO/.venv"
[[ -x .venv/bin/python ]] || python3.12 -m venv .venv
.venv/bin/pip install -q --disable-pip-version-check -r lab/requirements-ansible.txt
export PATH="$REPO/.venv/bin:$PATH"

log "Installing Ansible collections into $REPO/collections"
ansible-galaxy collection install -r requirements.yml -p collections >/dev/null

log "Building the lab: vault, CA, Nexus, and Nexus's repositories and accounts"
make lab-up

log "Lab ready. Next: make lab-demo (in $REPO) runs the whole pipeline; make lab-info shows where everything is."
