#!/usr/bin/env bash
# lab/demo.sh - the whole pipeline on the lab machine, with the same commands
# you'd run in a real environment (make lab-demo): build the transfer, publish
# it to Nexus, build Harbor, load the Broadcom bundles, verify. Needs make lab-up
# first.
#
#   bash lab/demo.sh [podman|docker]     (make lab-demo RUNTIME=docker)
#
# With a runtime, Harbor moves to it first: taken off the old one, its data
# kept, and the lab's runtime set (lab/runtime.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
# Lab names never go through a proxy, if this machine has one.
export no_proxy="${no_proxy:+$no_proxy,}localhost,127.0.0.1,.lab.internal" NO_PROXY="${NO_PROXY:+$NO_PROXY,}localhost,127.0.0.1,.lab.internal"
[[ -x .venv/bin/ansible-vault ]] && export PATH="$PWD/.venv/bin:$PATH"   # the lab's ansible-core

KIT_CONFIG="${KIT_CONFIG:-kits/lab.yml}"
ENV_NAME="lab"
step() { printf '\n\033[1m==== %s\033[0m\n\n' "$*"; }

runtime="${1:-}"
current="$(bash lab/runtime.sh)"
if [[ -n "$runtime" && "$runtime" != "$current" ]]; then
  [[ "$runtime" == podman || "$runtime" == docker ]] || { echo "RUNTIME is podman or docker, not $runtime" >&2; exit 1; }
  step "Moving Harbor from $current to $runtime: taking it off $current first (data is kept)"
  make remove-registry ENV="$ENV_NAME"
  bash lab/runtime.sh "$runtime" >/dev/null
fi

eval "$(bash lab/secrets.sh)"     # NEXUS_USER/NEXUS_PASSWORD for publish, HARBOR_PASSWORD for load
TRANSFER="$(python3 - "$KIT_CONFIG" <<'PY'
import os, sys, yaml
cfg = yaml.safe_load(open(sys.argv[1]))
out = os.path.expanduser((cfg.get("output") or {}).get("dir") or "~/kit-transfer")
if not os.path.isabs(out):
    out = os.path.join(os.path.dirname(os.path.abspath(sys.argv[1])), out)
print(os.path.join(out, cfg["name"]))
PY
)"

step "1/5  Connected side: check every source, then build the transfer"
python3 kit --config "$KIT_CONFIG" check
python3 kit --config "$KIT_CONFIG" fetch

step "2/5  Inside: check the transfer, stage it, upload the Harbor files to Nexus"
python3 kit publish --from "$TRANSFER" --env "$ENV_NAME"

step "3/5  Inside: build Harbor"
make build-registry ENV="$ENV_NAME"

step "4/5  Inside: load the Broadcom bundles into Harbor"
python3 kit load --env "$ENV_NAME"

step "5/5  Inside: verify Harbor"
make verify-registry ENV="$ENV_NAME"

step "Done: the pipeline ran end to end"
bash lab/info.sh
