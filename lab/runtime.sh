#!/usr/bin/env bash
# lab/runtime.sh - the container runtime Harbor runs on in the lab, kept in
# inventories/lab/group_vars/registry/runtime.yml. Like the vault, that file only
# exists inside the lab: the Windows script doesn't copy it in, and packages
# leave it out.
#
#   bash lab/runtime.sh            prints it; podman until it is set
#   bash lab/runtime.sh docker     sets it (make lab-demo RUNTIME=docker does this for you)
set -euo pipefail
cd "$(dirname "$0")/.."
file=inventories/lab/group_vars/registry/runtime.yml
want="${1:-}"
if [[ -z "$want" && -f "$file" ]]; then
  sed -n 's/^harbor_container_runtime: *\([a-z]*\).*/\1/p' "$file"
  exit 0
fi
want="${want:-podman}"
[[ "$want" == podman || "$want" == docker ]] || { echo "The lab's runtime is podman or docker, not $want" >&2; exit 1; }
printf -- '---\n# %s, written by lab/runtime.sh.\n# The runtime Harbor runs on in the lab: make lab-demo RUNTIME=podman|docker changes it.\n\nharbor_container_runtime: %s\n' \
  "$file" "$want" > "$file"
echo "$want"
