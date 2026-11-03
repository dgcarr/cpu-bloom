#!/usr/bin/env bash
# Builds release packages into dist/: a .deb, an .rpm, an Arch package (all
# installing under /usr) and a tarball with install.sh for other distributions.
#
# Usage: packaging/build.sh [--no-build] [--arch=x86_64|aarch64] [--version=X.Y.Z]
#
# Needs Processing (unless --no-build) and nfpm (https://nfpm.goreleaser.com).
# Without nfpm on PATH it runs nfpm's Docker image instead, if Docker works.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ARCH=x86_64
VERSION="$(git -C "$REPO" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${VERSION:-0.1.0}"
BUILD_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD_ARGS+=("$arg") ;;
    --arch=*) ARCH="${arg#--arch=}" ;;
    --version=*) VERSION="${arg#--version=}" ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
case "$ARCH" in
  x86_64) NFPM_ARCH=amd64 ;;
  aarch64) NFPM_ARCH=arm64 ;;
  *) echo "Unsupported arch: $ARCH (x86_64 or aarch64)" >&2; exit 2 ;;
esac

DIST="$REPO/dist"
STAGE="$DIST/root"
rm -rf "$STAGE"
mkdir -p "$DIST"
"$REPO/install.sh" "${BUILD_ARGS[@]}" --variant="linux-$ARCH" --prefix=/usr --destdir="$STAGE"

# Tarball: the staged app plus install.sh, for distributions without a package.
TARBALL="$DIST/cpu-bloom-$VERSION-linux-$ARCH.tar.gz"
tar -C "$REPO" -czf "$TARBALL" --transform "s#^#cpu-bloom-$VERSION/#" \
  install.sh scripts bin tray icons out README.md THEMES.md CHANGELOG.md LICENSE
echo "Wrote $TARBALL"

export NFPM_ARCH VERSION
export MAINTAINER="${MAINTAINER:-$(git -C "$REPO" config user.name) <$(git -C "$REPO" config user.email)>}"
nfpm_pkg() {
  if command -v nfpm >/dev/null 2>&1; then
    (cd "$REPO" && nfpm pkg "$@")
  elif docker info >/dev/null 2>&1; then
    docker run --rm -u "$(id -u):$(id -g)" -v "$REPO:/work" -w /work \
      -e NFPM_ARCH -e VERSION -e MAINTAINER goreleaser/nfpm:v2.47.0 pkg "$@"
  else
    echo "nfpm not found. Install it from https://nfpm.goreleaser.com/install/ (or install Docker)." >&2
    exit 1
  fi
}
for packager in deb rpm archlinux; do
  nfpm_pkg --config packaging/nfpm.yaml --packager "$packager" --target dist/
done
ls -lh "$DIST"
