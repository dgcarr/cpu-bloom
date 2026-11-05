#!/usr/bin/env bash
# Renders the Poppy theme's frames with Blender (Cycles, GPU if available).
#
#   poppy/render.sh                       full sequence -> cpu_bloom/data/poppy/{dim,bright}/
#   poppy/render.sh --preview 0,0.5,1     a few stills at 640px -> poppy/preview/
#
# Extra arguments are passed to poppy.py (--frames, --start, --res, --samples,
# --dim, --bright, --out). --start N resumes a stopped run at frame N.
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
  defaults=(--res 640 --samples 96 --out "$REPO/poppy/preview")
else
  defaults=(--out "$REPO/cpu_bloom/data/poppy")
fi
exec "$BLENDER" -b --factory-startup -P "$REPO/poppy/poppy.py" -- "${defaults[@]}" "$@"
