#!/usr/bin/env bash
# scripts/fetch_harbor.sh - get the Harbor files on a connected workstation
# (WSL on Windows, or any Linux box with internet access).
#
# Downloads Harbor's offline installer and checks its Sigstore signature. Then
# the compose provider: either podman-compose and python3-dotenv from EPEL 9
# (checked against EPEL's metadata, plus EPEL's signing key), or Docker's
# compose binary (checked against its published sha256). --with-docker-ce adds
# the Docker Engine RPMs as well, checked against Docker's repo metadata, for
# servers that run Docker and have no other way to get it. Last, it writes
# harbor_artifacts.yml and SHA256SUMS, laid out the way pull_harbor.sh,
# publish_harbor.sh and the roles expect.
#
# You don't normally run this by hand: python3 kit fetch runs it from kit.yml.
#
# Needs: bash, curl, python3, sha256sum, and cosign for the signature check:
#   curl -fLo cosign https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
#   sudo install -m 0755 cosign /usr/local/bin/cosign
#
# Usage:
#   scripts/fetch_harbor.sh [--version 2.15.2] [--out artifacts/harbor]
#       [--compose-provider podman-compose|docker-compose] [--docker-compose-version v2.x.y]
#       [--epel-mirror URL] [--release-url URL] [--no-verify-signature]
#       [--with-docker-ce [--docker-ce-repo URL]]
#
#   --version                  Harbor release. Default 2.15.2
#   --out                      Where the Harbor files go. Default artifacts/harbor
#   --compose-provider         podman-compose (EPEL RPMs, default) or docker-compose (Docker's binary)
#   --docker-compose-version   Docker Compose release for the docker-compose provider, e.g. v5.5.1 (the v is optional)
#   --epel-mirror              EPEL 9 x86_64 base URL. Default https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64
#   --release-url              Where Harbor's release files are. Default its GitHub release page
#   --no-verify-signature      Skip the cosign check (never for anything going into an environment)
#   --with-docker-ce           Add docker-ce, docker-ce-cli, containerd.io and the buildx and compose plugins
#   --docker-ce-repo           Docker's RHEL repository. Default https://download.docker.com/linux/rhel/9/x86_64/stable
#
# Exit codes: 0 written, 1 usage or environment problem, 2 a download failed its
# check (nothing is written to --out).
set -euo pipefail

VERSION="2.15.2"
OUT="artifacts/harbor"
PROVIDER="podman-compose"
DC_VERSION=""
EPEL="https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64"
EPEL_KEY_URL="https://dl.fedoraproject.org/pub/epel/RPM-GPG-KEY-EPEL-9"
VERIFY=true
RELEASE_URL=""
WITH_DOCKER_CE=false
DOCKER_REPO="https://download.docker.com/linux/rhel/9/x86_64/stable"
DOCKER_KEY_URL="https://download.docker.com/linux/rhel/gpg"
DOCKER_RPMS="docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

log()   { printf '%s  %s\n' "$(date '+%F %T')" "$*"; }
die()   { log "ERROR: $1" >&2; exit "${2:-1}"; }
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
need()  { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || die "$1 needs a value (see --help)"; }

while [[ $# -gt 0 ]]; do
  if [[ "$1" == --*=* ]]; then set -- "${1%%=*}" "${1#*=}" "${@:2}"; fi   # --option=value works too
  case "$1" in
    --version)                need "$@"; VERSION="${2#v}"; shift 2 ;;
    --out)                    need "$@"; OUT="${2%/}"; shift 2 ;;
    --compose-provider)       need "$@"; PROVIDER="$2"; shift 2 ;;
    --docker-compose-version) need "$@"; DC_VERSION="$2"; shift 2 ;;
    --epel-mirror)            need "$@"; EPEL="${2%/}"; shift 2 ;;
    --release-url)            need "$@"; RELEASE_URL="${2%/}"; shift 2 ;;
    --no-verify-signature)    VERIFY=false; shift ;;
    --with-docker-ce)         WITH_DOCKER_CE=true; shift ;;
    --docker-ce-repo)         need "$@"; DOCKER_REPO="${2%/}"; shift 2 ;;
    -h|--help)                usage; exit 0 ;;
    *)                        die "unknown option: $1 (see --help)" ;;
  esac
done

[[ "$PROVIDER" == podman-compose || "$PROVIDER" == docker-compose ]] \
  || die "--compose-provider must be podman-compose or docker-compose"
[[ "$PROVIDER" != docker-compose || -n "$DC_VERSION" ]] \
  || die "--docker-compose-version is required with --compose-provider docker-compose"
for tool in curl python3 sha256sum find sort xargs; do
  command -v "$tool" >/dev/null || die "$tool is required"
done
if $VERIFY; then
  command -v cosign >/dev/null || die "cosign is required to check Harbor's signature (see --help for the install line)"
fi

INSTALLER="harbor-offline-installer-v${VERSION}.tgz"
RELEASE_URL="${RELEASE_URL:-https://github.com/goharbor/harbor/releases/download/v${VERSION}}"
IDENTITY="https://github.com/goharbor/harbor/.github/workflows/publish_release.yml@refs/tags/v${VERSION}"
ISSUER="https://token.actions.githubusercontent.com"
STAMP="$(date '+%Y%m%d-%H%M%S')"
[[ -z "$DC_VERSION" ]] || DC_VERSION="v${DC_VERSION#v}"     # Docker's tags start with v
DC_URL="https://github.com/docker/compose/releases/download/${DC_VERSION}/docker-compose-linux-x86_64"

mkdir -p "$(dirname "$OUT")"
WORK="$(mktemp -d "$(dirname "$OUT")/.fetch-harbor-${STAMP}-XXXX")"
FILES="$WORK/harbor"
mkdir -p "$FILES"
trap 'rm -rf -- "$WORK"' EXIT
fail() { die "$1, so nothing was written to $OUT" 2; }

# Downloads the newest build of each named package from a yum repository and
# checks it against that repository's own metadata. Used for EPEL and Docker.
REPOFETCH="$WORK/repofetch.py"
cat > "$REPOFETCH" <<'PY'
import gzip, bz2, hashlib, http.client, lzma, re, sys, time, urllib.request
import xml.etree.ElementTree as ET

label, base, dest, names = sys.argv[1], sys.argv[2].rstrip("/") + "/", sys.argv[3], sys.argv[4:]
ns = {"r": "http://linux.duke.edu/metadata/repo", "c": "http://linux.duke.edu/metadata/common"}

def fetch(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return r.read()
        except (OSError, http.client.HTTPException) as e:
            if attempt == 2:
                raise SystemExit(f"download failed: {url}: {e}")
            time.sleep(5)

def unpack(raw):
    if raw[:2] == b"\x1f\x8b":
        return gzip.decompress(raw)
    if raw[:6] == b"\xfd7zXZ\x00":
        return lzma.decompress(raw)
    if raw[:3] == b"BZh":
        return bz2.decompress(raw)
    if raw[:4] == b"\x28\xb5\x2f\xfd":            # zstd, as Docker's repository uses
        try:
            from compression import zstd          # Python 3.14 and later
            return zstd.decompress(raw)
        except ImportError:
            pass
        try:
            import zstandard
            return zstandard.ZstdDecompressor().decompressobj().decompress(raw)
        except ImportError:
            pass
        import shutil, subprocess
        tool = shutil.which("zstd") or shutil.which("unzstd")
        if tool:
            return subprocess.run([tool, "-dc"], input=raw, stdout=subprocess.PIPE, check=True).stdout
        raise SystemExit("this repository's metadata is zstd-compressed: install zstd "
                         "(sudo dnf install zstd, or sudo apt-get install zstd) and run again")
    raise SystemExit("the repository's metadata uses a compression this script can't read")

def vercmp(a, b):
    """rpm's version comparison, without the rarely used caret."""
    sa, sb = re.findall(r"[0-9]+|[A-Za-z]+|~", a), re.findall(r"[0-9]+|[A-Za-z]+|~", b)
    while sa or sb:
        x, y = (sa.pop(0) if sa else None), (sb.pop(0) if sb else None)
        if x == "~" or y == "~":
            if x != y:
                return -1 if x == "~" else 1
            continue
        if x is None or y is None:
            return -1 if x is None else 1
        if x.isdigit() != y.isdigit():
            return 1 if x.isdigit() else -1
        if x.isdigit():
            x, y = int(x), int(y)
        if x != y:
            return 1 if x > y else -1
    return 0

repomd = ET.fromstring(fetch(base + "repodata/repomd.xml"))
primary = next(d.find("r:location", ns).get("href") for d in repomd.findall("r:data", ns) if d.get("type") == "primary")
root = ET.fromstring(unpack(fetch(base + primary)))

def newer(a, b):
    """True when epoch-version-release a is newer than b."""
    if a[0] != b[0]:
        return a[0] > b[0]
    return (vercmp(a[1], b[1]) or vercmp(a[2], b[2])) > 0

best = {}
for p in root.findall("c:package", ns):
    name = p.find("c:name", ns).text
    if name not in names or p.find("c:arch", ns).text not in ("noarch", "x86_64"):
        continue
    v = p.find("c:version", ns)
    evr = (int(v.get("epoch") or 0), v.get("ver"), v.get("rel"))
    if name not in best or newer(evr, best[name][0]):
        ck = p.find("c:checksum", ns)
        best[name] = (evr, p.find("c:location", ns).get("href"), ck.get("type"), ck.text)

missing = [n for n in names if n not in best]
if missing:
    raise SystemExit(f"not found in {label}: {', '.join(missing)}")

for name in names:
    evr, href, ctype, digest = best[name]
    data = fetch(base + href)
    if hashlib.new(ctype, data).hexdigest() != digest:
        raise SystemExit(f"{href} does not match {label}'s {ctype} checksum")
    with open(f"{dest}/{href.rsplit('/', 1)[-1]}", "wb") as f:
        f.write(data)
    print(f"  {href.rsplit('/', 1)[-1]}  ({ctype} matches {label} metadata)")
PY
get()  { curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 --progress-bar -o "$1" "$2"; }

# --- 0. Small files first, so a wrong version or a blocked site fails before the large download
log "Checking the sources"
if [[ "$PROVIDER" == podman-compose ]]; then
  curl -fsSL --retry 2 --connect-timeout 30 -o /dev/null "$EPEL/repodata/repomd.xml" \
    || die "EPEL is not reachable at $EPEL (see --epel-mirror)"
else
  get "$WORK/docker-compose.sha256" "$DC_URL.sha256" \
    || die "docker-compose $DC_VERSION not found; check --docker-compose-version against https://github.com/docker/compose/releases"
fi
if $WITH_DOCKER_CE; then
  curl -fsSL --retry 2 --connect-timeout 30 -o /dev/null "$DOCKER_REPO/repodata/repomd.xml" \
    || die "Docker's repository is not reachable at $DOCKER_REPO (see --docker-ce-repo)"
fi
get "$FILES/$INSTALLER.sigstore.json" "$RELEASE_URL/$INSTALLER.sigstore.json" \
  || { $VERIFY && die "download of $INSTALLER.sigstore.json failed; check --version"; log "No signature bundle downloaded"; }

# --- 1. Harbor installer and its Sigstore signature ---------------------------
log "Downloading Harbor ${VERSION}"
get "$FILES/$INSTALLER" "$RELEASE_URL/$INSTALLER" || die "download of $INSTALLER failed"

if $VERIFY; then
  log "Checking Harbor's signature (Sigstore, release workflow for v${VERSION})"
  cosign verify-blob \
    --bundle "$FILES/$INSTALLER.sigstore.json" \
    --certificate-oidc-issuer "$ISSUER" \
    --certificate-identity "$IDENTITY" \
    "$FILES/$INSTALLER" || fail "$INSTALLER failed the signature check"
else
  log "WARNING: signature not checked (--no-verify-signature)"
fi

# --- 2. Compose provider ------------------------------------------------------------
if [[ "$PROVIDER" == podman-compose ]]; then
  log "Downloading podman-compose and python3-dotenv from EPEL 9"
  mkdir -p "$FILES/podman"
  python3 "$REPOFETCH" EPEL "$EPEL" "$FILES/podman" podman-compose python3-dotenv || fail "an EPEL package failed its check"
  get "$FILES/RPM-GPG-KEY-EPEL-9" "$EPEL_KEY_URL" || die "download of the EPEL signing key failed"
else
  log "Downloading docker-compose ${DC_VERSION}"
  get "$FILES/docker-compose-linux-x86_64" "$DC_URL" || die "download of docker-compose failed"
  [[ "$(sha256sum "$FILES/docker-compose-linux-x86_64" | awk '{print $1}')" == "$(awk '{print $1}' "$WORK/docker-compose.sha256")" ]] \
    || fail "docker-compose does not match its published checksum"
  chmod 0755 "$FILES/docker-compose-linux-x86_64"
fi

if $WITH_DOCKER_CE; then
  log "Downloading Docker Engine from $DOCKER_REPO"
  mkdir -p "$FILES/docker"
  # shellcheck disable=SC2086  # the package names are meant to split
  python3 "$REPOFETCH" Docker "$DOCKER_REPO" "$FILES/docker" $DOCKER_RPMS || fail "a Docker package failed its check"
  get "$FILES/RPM-GPG-KEY-docker" "$DOCKER_KEY_URL" || die "download of Docker's signing key failed"
fi

# --- 3. Manifest and SHA256SUMS ------------------------------------------------------
SHA="$(sha256sum "$FILES/$INSTALLER" | awk '{print $1}')"
{
  printf -- '---\n'
  printf '# group_vars/registry/harbor_artifacts.yml\n#\n'
  printf '# Written by scripts/fetch_harbor.sh on %s. kit publish (or make pull-harbor)\n' "$(date '+%F')"
  printf '# copies it into inventories/<env>/group_vars/registry/. The roles check the\n'
  printf '# Harbor files against these checksums once they land.\n\n'
  printf 'harbor_version:           "%s"\n' "$VERSION"
  printf 'harbor_installer_file:    "%s"\n' "$INSTALLER"
  printf 'harbor_installer_sha256:  "%s"\n' "$SHA"
  if [[ "$PROVIDER" == docker-compose ]]; then
    printf 'podman_offline_docker_compose_sha256: "%s"\n' "$(sha256sum "$FILES/docker-compose-linux-x86_64" | awk '{print $1}')"
  fi
} > "$FILES/harbor_artifacts.yml"
( cd "$FILES" && find . -type f -print0 | sort -z | xargs -0 sha256sum ) > "$WORK/SHA256SUMS"
mv "$WORK/SHA256SUMS" "$FILES/SHA256SUMS"

# --- 4. Put it in place -----------------------------------------------------------------
if [[ -e "$OUT" ]]; then
  mv "$OUT" "$OUT.previous-$STAMP"
  log "Previous copy kept as $OUT.previous-$STAMP"
fi
mv "$FILES" "$OUT"
log "Harbor files written to $OUT: Harbor $VERSION, sha256 $SHA"
if [[ -z "${KIT_RUNNING:-}" ]]; then   # python3 kit prints its own next steps
  log "Next: carry $OUT across, then inside the environment:"
  log "  make pull-harbor    ENV=<env> FROM=<where you put it>"
  log "  make publish-harbor ENV=<env> NEXUS=https://<nexus>"
fi
