#!/usr/bin/env bash
# scripts/pull_harbor.sh - copy the Harbor files into the environment, check
# every one, and stage them where the playbooks look for them.
#
# Run it inside the environment, on whichever host holds artifact_staging: the
# Ansible control host (artifact_staged_on: controller) or the registry server
# (artifact_staged_on: target). The copy is always started from the inside, so
# the connected side never needs a way in.
#
# python3 kit publish runs this for you.
#
# Usage:
#   scripts/pull_harbor.sh --from SOURCE [--to DIR] [--inventory DIR] [--keep N] [--dry-run]
#
#   --from       Where the Harbor files are (required):
#                  user@host:/path/artifacts/harbor   over scp, where the environment can reach it
#                  /media/transfer/harbor             transfer media or a mounted share, where it can't
#   --to         Staging root; the files land in <to>/harbor. Match artifact_staging
#                in group_vars/all. Default: /var/staging/artifacts
#   --inventory  Inventory directory to receive harbor_artifacts.yml in
#                group_vars/registry/, e.g. inventories/prod. Leave out on a
#                host without the Ansible repo, and commit the manifest by hand.
#   --keep       How many older copies to keep beside the current one. Default: 1
#   --dry-run    Show what would happen and change nothing.
#
# Exit codes: 0 staged, 1 usage or environment problem, 2 a check failed (the copy
# is left in <to>/.incoming-harbor-<timestamp>-* to look at; nothing is staged).
set -euo pipefail

NAME="harbor"
MANIFEST="harbor_artifacts.yml"
SOURCE=""
STAGING="/var/staging/artifacts"
INVENTORY_DIR=""
KEEP=1
DRY_RUN=false

log()  { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die()  { log "ERROR: $1" >&2; exit "${2:-1}"; }
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

need() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 needs a value (see --help)"; }

while [[ $# -gt 0 ]]; do
  if [[ "$1" == --*=* ]]; then set -- "${1%%=*}" "${1#*=}" "${@:2}"; fi   # --option=value works too
  case "$1" in
    --from)      need "$@"; SOURCE="$2"; shift 2 ;;
    --to)        need "$@"; STAGING="$2"; shift 2 ;;
    --inventory) need "$@"; INVENTORY_DIR="$2"; shift 2 ;;
    --keep)      need "$@"; KEEP="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           die "unknown option: $1 (see --help)" ;;
  esac
done

[[ -n "$SOURCE" ]] || { usage >&2; die "--from is required"; }
[[ "$KEEP" =~ ^[0-9]+$ ]] || die "--keep must be a whole number"
SOURCE="${SOURCE%/}"
STAGING="${STAGING%/}"
INVENTORY_DIR="${INVENTORY_DIR%/}"
for tool in sha256sum awk sort comm df du; do
  command -v "$tool" >/dev/null || die "$tool is required"
done

REMOTE=false
if [[ "$SOURCE" == *:* && "$SOURCE" != /* ]]; then
  REMOTE=true
  command -v scp >/dev/null || die "scp is required for a remote source"
  REMOTE_HOST="${SOURCE%%:*}"
  REMOTE_PATH="${SOURCE#*:}"
else
  [[ -d "$SOURCE" ]] || die "$SOURCE is not a directory"
fi

STAMP="$(date '+%Y%m%d-%H%M%S')"
CURRENT="$STAGING/$NAME"

# --- space check (best effort) -----------------------------------------------
size_kb=""
if $REMOTE; then
  size_kb="$(ssh -o BatchMode=yes "$REMOTE_HOST" "du -sk '$REMOTE_PATH'" 2>/dev/null | awk '{print $1}')" || size_kb=""
else
  size_kb="$(du -sk "$SOURCE" | awk '{print $1}')"
fi

if $DRY_RUN; then
  log "dry-run: would pull $SOURCE (${size_kb:-unknown} KB) into $STAGING/.incoming-$NAME-$STAMP-*"
  log "dry-run: would verify every file against SHA256SUMS and check $MANIFEST"
  log "dry-run: would stage it as $CURRENT, keeping $KEEP older copies"
  [[ -n "$INVENTORY_DIR" ]] && log "dry-run: would copy $MANIFEST to $INVENTORY_DIR/group_vars/registry/"
  exit 0
fi

mkdir -p "$STAGING"
[[ -w "$STAGING" ]] || die "$STAGING is not writable (run with sudo, or fix its ownership)"
if [[ -n "$size_kb" ]]; then
  free_kb="$(df -Pk "$STAGING" | awk 'NR==2 {print $4}')"
  (( free_kb > size_kb * 11 / 10 )) || die "$STAGING has ${free_kb} KB free; this needs about ${size_kb} KB"
fi

# --- 1. pull -------------------------------------------------------------------
INCOMING="$(mktemp -d "$STAGING/.incoming-$NAME-$STAMP-XXXX")"
NEWDIR="$INCOMING/$NAME"
log "Pulling $SOURCE"
if $REMOTE; then
  scp -rpq "$SOURCE" "$NEWDIR" || { rm -rf -- "$INCOMING"; die "scp from $SOURCE failed"; }
else
  cp -a "$SOURCE" "$NEWDIR" || { rm -rf -- "$INCOMING"; die "copy from $SOURCE failed"; }
fi

reject() { log "Left in $INCOMING so you can look at it"; die "$1, so nothing was staged" 2; }

# --- 2. verify -----------------------------------------------------------------
[[ -f "$NEWDIR/SHA256SUMS" ]] || reject "SHA256SUMS is missing"
[[ -f "$NEWDIR/$MANIFEST" ]]  || reject "$MANIFEST is missing"

log "Verifying every file against SHA256SUMS"
( cd "$NEWDIR" && sha256sum -c --quiet SHA256SUMS ) || reject "checksum mismatch"

unlisted="$(cd "$NEWDIR" && comm -23 \
  <(find . -type f ! -name SHA256SUMS | sort) \
  <(awk '{print $2}' SHA256SUMS | sort))"
[[ -z "$unlisted" ]] || reject "files not covered by SHA256SUMS: $(echo "$unlisted" | tr '\n' ' ')"

field() { awk -F': *' -v k="$1" '$1 == k { gsub(/"/, "", $2); print $2 }' "$2"; }
VERSION="$(field harbor_version "$NEWDIR/$MANIFEST")"
INSTALLER="$(field harbor_installer_file "$NEWDIR/$MANIFEST")"
SHA="$(field harbor_installer_sha256 "$NEWDIR/$MANIFEST")"
[[ -n "$VERSION" && -n "$INSTALLER" && ${#SHA} -eq 64 ]] || reject "$MANIFEST is incomplete"
[[ -f "$NEWDIR/$INSTALLER" ]] || reject "$INSTALLER, named in $MANIFEST, is missing"
[[ "$(sha256sum "$NEWDIR/$INSTALLER" | awk '{print $1}')" == "$SHA" ]] \
  || reject "$INSTALLER does not match $MANIFEST"
log "Every file checks out: Harbor $VERSION"

# --- 3. stage ------------------------------------------------------------------
PREVIOUS_VERSION=""
if [[ -d "$CURRENT" ]]; then
  PREVIOUS_VERSION="$(field harbor_version "$CURRENT/$MANIFEST" 2>/dev/null || true)"
  previous_dir="$STAGING/$NAME.previous-$STAMP"
  [[ ! -e "$previous_dir" ]] || previous_dir="$previous_dir-$$"
  mv "$CURRENT" "$previous_dir"
fi
mv "$NEWDIR" "$CURRENT"
rmdir "$INCOMING"
chmod -R u=rwX,g=rX,o= "$CURRENT"
# Run with sudo, the files would end up readable only by root, but Ansible on
# the control host runs as you. Hand them back to whoever ran sudo.
if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  chown -R "$SUDO_USER": "$CURRENT"
fi
if command -v restorecon >/dev/null; then restorecon -R "$CURRENT" 2>/dev/null || true; fi

mapfile -t previous < <(find "$STAGING" -maxdepth 1 -type d -name "$NAME.previous-*" | sort -r)
if (( ${#previous[@]} > KEEP )); then
  for old in "${previous[@]:KEEP}"; do
    rm -rf -- "$old"
    log "Removed older copy $old"
  done
fi

# --- 4. inventory ----------------------------------------------------------------
if [[ -n "$INVENTORY_DIR" ]]; then
  target="$INVENTORY_DIR/group_vars/registry/$MANIFEST"
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && ! cmp -s "$target" "$CURRENT/$MANIFEST"; then
    cp -p "$target" "$target.previous"      # one level of undo; git has the rest
  fi
  cp "$CURRENT/$MANIFEST" "$target"
  log "Updated $target"
fi

# --- 5. record -------------------------------------------------------------------
printf '%s\t%s\t%s\t%s\t%s\n' "$STAMP" "$(id -un)" "$SOURCE" "$VERSION" "$SHA" >> "$STAGING/pull.log"

log "Staged Harbor $VERSION in $CURRENT${PREVIOUS_VERSION:+ (previously $PREVIOUS_VERSION)}"
if [[ -z "${KIT_RUNNING:-}" ]]; then   # python3 kit prints its own next steps
  log "Next: make publish-harbor ENV=<environment> NEXUS=https://<nexus>, then make build-registry ENV=<environment>"
  log "      (with artifact_source: staged, skip the publish)"
fi
