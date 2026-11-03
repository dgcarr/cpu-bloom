#!/usr/bin/env bash
# Exports CPU Bloom with Processing into out/ (or OUT) and prepares the export
# for installing: a launcher that execs java with a capped heap, a runnable
# jspawnhelper, and no JDK files that only matter for development.
#
# Usage: scripts/build-export.sh [--no-build] [--variant=linux-x86_64|linux-aarch64] [OUT]
# Set PROCESSING=/path/to/Processing if it isn't in /opt/processing.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROCESSING="${PROCESSING:-/opt/processing/bin/Processing}"
VARIANT=linux-x86_64
BUILD=1
OUT="$REPO/out"
for arg in "$@"; do
  case "$arg" in
    --no-build) BUILD=0 ;;
    --variant=*) VARIANT="${arg#--variant=}" ;;
    -*) echo "Unknown option: $arg" >&2; exit 2 ;;
    *) OUT="$(realpath -m "$arg")" ;;
  esac
done

if [[ $BUILD == 1 ]]; then
  echo "Exporting with Processing ($VARIANT)…"
  "$PROCESSING" cli --force --sketch="$REPO/cpu_bloom" --output="$OUT" \
    --variant="$VARIANT" --export
fi
[[ -x "$OUT/cpu_bloom" ]] || { echo "No export in $OUT; run without --no-build." >&2; exit 1; }

# Processing 4.5.7's .deb ships this helper without +x, and the export copies
# it; without it Java can't start subprocesses and JOGL fails to load.
chmod +x "$OUT/java/lib/jspawnhelper"
# Processing's launcher script runs java as a child, so signalling the script
# (as the indicator does to close the window) would orphan the JVM. Make it
# exec java instead, so the launcher's PID is the JVM's PID.
# Also cap the heap: by default Java may grow it to a quarter of RAM, and
# for a monitor that runs all day it does. 320 MB is ample for every theme.
# Idempotent, so --no-build can re-patch an export patched before.
sed -E -i 's#^(exec )?\$APPDIR/java/bin/java (-Xmx[0-9]+m )?#exec $APPDIR/java/bin/java -Xmx320m #' "$OUT/cpu_bloom"
grep -q '^exec \$APPDIR/java/bin/java -Xmx' "$OUT/cpu_bloom" || { echo "Could not patch $OUT/cpu_bloom launcher." >&2; exit 1; }
# The export bundles a full JDK. Sources, jmods, headers, man pages and the
# compiler's symbol file are never used at run time and are half its size.
rm -rf "$OUT/java/src.zip" "$OUT/java/lib/src.zip" "$OUT/java/jmods" "$OUT/java/include" \
  "$OUT/java/man" "$OUT/java/lib/ct.sym"
