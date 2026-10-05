#!/usr/bin/env bash
# lab/info.sh - where the lab's services are and how to sign in (make lab-info).
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x .venv/bin/ansible-vault ]] && export PATH="$PWD/.venv/bin:$PATH"   # the lab's ansible-core
eval "$(bash lab/secrets.sh)"
admin=$(ansible-vault view --vault-password-file .vault_pass inventories/lab/group_vars/all/vault.yml \
        | python3 -c 'import sys, yaml; print(yaml.safe_load(sys.stdin)["vault_nexus_admin_password"])')
runtime="$(bash lab/runtime.sh)"
cat <<INFO

  Harbor   https://harbor.lab.internal       admin / ${HARBOR_PASSWORD}      (on ${runtime})
  Nexus    http://localhost:8081             admin / ${admin}
           upload account                    ${NEXUS_USER} / ${NEXUS_PASSWORD}
  Lab CA   /etc/harbor-lab/pki/ca.crt

  From Windows, add this line to C:\Windows\System32\drivers\etc\hosts (as administrator)
      127.0.0.1 harbor.lab.internal
  and trust the lab CA for the browser, in PowerShell (no administrator needed; Windows asks you to confirm):
      Import-Certificate -FilePath \\\\wsl.localhost\\harbor-lab\\etc\\harbor-lab\\pki\\ca.crt -CertStoreLocation Cert:\\CurrentUser\\Root

INFO
