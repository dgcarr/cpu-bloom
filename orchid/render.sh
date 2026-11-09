#!/usr/bin/env bash
# Renders the Orchid theme's frames with Blender (Cycles, GPU if available).
#
#   orchid/render.sh                      full sequence -> cpu_bloom/data/orchid/{dim,bright}/
#   orchid/render.sh --preview 0,0.5,1    a few stills at 640px -> orchid/preview/
#   orchid/render.sh --preview 1 --res 1280 --border 0.3,0.28,0.7,0.72
#                                         a close-up of the open flower's centre
#
# Extra arguments are passed to orchid.py (--frames, --start, --res, --samples,
# --dim, --bright, --border, --out). --start N resumes a stopped run at frame N.
# Uses Blender on PATH; set BLENDER=/path/to/blender to override.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${BLENDER:-}" ]]; then
  BLENDER="$(command -v blender || true)"
fi
[[ -x "$BLENDER" ]] || { echo "Blender not found; set BLENDER=/path/to/blender" >&2; exit 1; }

# Defaults go first: argparse keeps the last occurrence of a flag, so anything
# the caller passes (--res, --samples, --out) overrides them.
if [[ " $* " == *" --preview "* ]]; then
  defaults=(--res 640 --samples 96 --out "$REPO/orchid/preview")
else
  defaults=(--out "$REPO/cpu_bloom/data/orchid")
fi
exec "$BLENDER" -b --factory-startup -P "$REPO/orchid/orchid.py" -- "${defaults[@]}" "$@"
