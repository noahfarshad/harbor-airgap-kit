#!/usr/bin/env bash
# lab/secrets.sh - print shell exports for the lab's demo, read from the vault:
#   eval "$(bash lab/secrets.sh)"
# NEXUS_USER/NEXUS_PASSWORD (upload account) for kit publish, HARBOR_PASSWORD for kit load.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x .venv/bin/ansible-vault ]] && export PATH="$PWD/.venv/bin:$PATH"   # the lab's ansible-core
ansible-vault view --vault-password-file .vault_pass inventories/lab/group_vars/all/vault.yml | python3 -c '
import shlex, sys, yaml
v = yaml.safe_load(sys.stdin)
for name, key in (("NEXUS_USER", "vault_nexus_upload_user"), ("NEXUS_PASSWORD", "vault_nexus_upload_password"),
                  ("HARBOR_USER", None), ("HARBOR_PASSWORD", "vault_harbor_admin_password")):
    value = "admin" if key is None else v[key]
    print("export %s=%s" % (name, shlex.quote(str(value))))
'
