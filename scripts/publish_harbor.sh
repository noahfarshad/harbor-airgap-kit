#!/usr/bin/env bash
# scripts/publish_harbor.sh - upload the staged Harbor files to the
# environment's Nexus, where the roles and dnf read them.
#
#   raw repository (--raw-repo)   harbor/<installer, signature, manifest, SHA256SUMS,
#                                 EPEL key, docker-compose binary if present>
#   yum repository (--yum-repo)   podman-compose and python3-dotenv only
#
# Run it after scripts/pull_harbor.sh has checked and staged the files (python3
# kit publish runs both). It checks SHA256SUMS again before uploading anything,
# and only ever puts the two EPEL packages in the yum repository, so a routine
# dnf update can't pick up anything else from it.
#
# Usage:
#   scripts/publish_harbor.sh --nexus https://nexus.example.com
#       [--dir /var/staging/artifacts/harbor] [--raw-repo vmware-raw]
#       [--yum-repo harbor-epel] [--yum-path ""] [--user NAME] [--cacert FILE] [--dry-run]
#
#   --yum-path   Sub-path inside the yum repository, if its repodata depth is not 0
#   --cacert     CA bundle for Nexus's certificate, e.g. /etc/ipa/ca.crt
#
# Credentials: --user (or NEXUS_USER) and NEXUS_PASSWORD; prompted for when unset.
# The password never appears on a command line.
#
# Exit codes: 0 published, 1 usage or upload problem, 2 a checksum didn't match.
set -euo pipefail

NEXUS=""
FILES="/var/staging/artifacts/harbor"
RAW_REPO="vmware-raw"
YUM_REPO="harbor-epel"
YUM_PATH=""
NEXUS_USER="${NEXUS_USER:-}"
CACERT=""
DRY_RUN=false
EPEL_RPMS="podman-compose python3-dotenv"

log()   { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die()   { log "ERROR: $1" >&2; exit "${2:-1}"; }
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
need()  { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 needs a value (see --help)"; }

while [[ $# -gt 0 ]]; do
  if [[ "$1" == --*=* ]]; then set -- "${1%%=*}" "${1#*=}" "${@:2}"; fi   # --option=value works too
  case "$1" in
    --nexus)    need "$@"; NEXUS="${2%/}"; shift 2 ;;
    --dir)      need "$@"; FILES="${2%/}"; shift 2 ;;
    --raw-repo) need "$@"; RAW_REPO="$2"; shift 2 ;;
    --yum-repo) need "$@"; YUM_REPO="$2"; shift 2 ;;
    --yum-path) need "$@"; YUM_PATH="${2#/}"; YUM_PATH="${YUM_PATH%/}"; shift 2 ;;
    --user)     need "$@"; NEXUS_USER="$2"; shift 2 ;;
    --cacert)   need "$@"; CACERT="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          die "unknown option: $1 (see --help)" ;;
  esac
done

[[ -n "$NEXUS" ]] || { usage >&2; die "--nexus is required"; }
[[ -d "$FILES" ]] || die "$FILES is not a directory; run make pull-harbor first"
for tool in curl sha256sum awk sort comm find; do
  command -v "$tool" >/dev/null || die "$tool is required"
done

# --- 1. check everything again ----------------------------------------------------
[[ -f "$FILES/SHA256SUMS" && -f "$FILES/harbor_artifacts.yml" ]] || die "$FILES has no SHA256SUMS or harbor_artifacts.yml" 2
log "Verifying $FILES against SHA256SUMS"
( cd "$FILES" && sha256sum -c --quiet SHA256SUMS ) || die "checksum mismatch, nothing published" 2
unlisted="$(cd "$FILES" && comm -23 <(find . -type f ! -name SHA256SUMS | sort) <(awk '{print $2}' SHA256SUMS | sort))"
[[ -z "$unlisted" ]] || die "files not covered by SHA256SUMS: $(echo "$unlisted" | tr '\n' ' '), nothing published" 2

# --- 2. work out what goes where --------------------------------------------------
raw_files=()
while IFS= read -r f; do raw_files+=("$f"); done < <(cd "$FILES" && find . -type f ! -path './podman/*' | sed 's#^\./##' | sort)

yum_files=()
skipped=()
if [[ -d "$FILES/podman" ]]; then
  while IFS= read -r f; do
    name="$(basename "$f" | sed -E 's/-[^-]+-[^-]+\.[^.]+\.rpm$//')"
    if [[ " $EPEL_RPMS " == *" $name "* ]]; then yum_files+=("$f"); else skipped+=("$(basename "$f")"); fi
  done < <(cd "$FILES" && find ./podman -type f -name '*.rpm' | sed 's#^\./##' | sort)
fi

raw_base="$NEXUS/repository/$RAW_REPO/harbor"
yum_base="$NEXUS/repository/$YUM_REPO${YUM_PATH:+/$YUM_PATH}"

log "Raw repository: $raw_base/"
for f in "${raw_files[@]}"; do log "  $f"; done
if (( ${#yum_files[@]} > 0 )); then
  log "Yum repository: $yum_base/"
  for f in "${yum_files[@]}"; do log "  $(basename "$f")"; done
fi
for f in "${skipped[@]}"; do log "  not published (not one of: $EPEL_RPMS): $f"; done
$DRY_RUN && { log "dry-run: nothing uploaded"; exit 0; }

# --- 3. upload ------------------------------------------------------------------------
if [[ -z "$NEXUS_USER" ]]; then read -rp "Nexus user: " NEXUS_USER; fi
if [[ -z "${NEXUS_PASSWORD:-}" ]]; then read -rsp "Nexus password for $NEXUS_USER: " NEXUS_PASSWORD; echo; fi
curl_auth() {
  local cred
  cred="$(printf '%s:%s' "$NEXUS_USER" "$NEXUS_PASSWORD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf 'user = "%s"\n' "$cred"
}
curl_opts=(--fail --show-error --silent --retry 2 --connect-timeout 30)
[[ -n "$CACERT" ]] && curl_opts+=(--cacert "$CACERT")

put() {   # put <local file> <url>
  curl_auth | curl "${curl_opts[@]}" -K - --upload-file "$1" "$2" >/dev/null || die "upload failed: $2"
  local size remote
  size="$(wc -c < "$1" | tr -d ' ')"
  remote="$(curl_auth | curl "${curl_opts[@]}" -K - --head "$2" | awk 'tolower($1) == "content-length:" {gsub("\r", ""); print $2}' | tail -1)"
  [[ -z "$remote" || "$remote" == "$size" ]] || die "size on Nexus ($remote) differs from the local file ($size): $2"
  log "  published $(basename "$1")"
}

log "Uploading to $NEXUS"
for f in "${raw_files[@]}"; do put "$FILES/$f" "$raw_base/$f"; done
for f in "${yum_files[@]}"; do put "$FILES/$f" "$yum_base/$(basename "$f")"; done

VERSION="$(awk -F': *' '$1 == "harbor_version" { gsub(/"/, "", $2); print $2 }' "$FILES/harbor_artifacts.yml")"
log "Published Harbor $VERSION to $NEXUS"
[[ -n "${KIT_RUNNING:-}" ]] || log "Next: commit inventories/<env>/group_vars/registry/harbor_artifacts.yml, then make build-registry ENV=<env>"
