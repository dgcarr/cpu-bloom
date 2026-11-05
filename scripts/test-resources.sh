#!/usr/bin/env bash
# Build first with scripts/build-export.sh. Tests use an isolated disposable cache.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
JAVA="$REPO/out/java/bin"
"$JAVA/javac" -cp "$REPO/out/lib/*" -d "$TEST_DIR" "$REPO/tests/ResourceRegression.java" "$REPO/tests/SamplerTimeout.java"
XDG_CACHE_HOME="$TEST_DIR/cache" "$JAVA/java" -Djava.awt.headless=true \
  -cp "$TEST_DIR:$REPO/out/lib/*" ResourceRegression "$REPO/cpu_bloom/data/poppy/dim/poppy_000.jpg"

mkdir -p "$TEST_DIR/bin"
printf '#!/bin/sh\nexec sleep 20\n' > "$TEST_DIR/bin/nvidia-smi"
chmod +x "$TEST_DIR/bin/nvidia-smi"
PATH="$TEST_DIR/bin:$PATH" "$JAVA/java" -cp "$TEST_DIR:$REPO/out/lib/*" SamplerTimeout

# Every pre-rendered theme needs the same number of frames in each light level.
for theme in poppy orchid; do
  dim=$(ls "$REPO/cpu_bloom/data/$theme/dim" | grep -c "^${theme}_[0-9]*\.jpg$" || true)
  bright=$(ls "$REPO/cpu_bloom/data/$theme/bright" | grep -c "^${theme}_[0-9]*\.jpg$" || true)
  [[ $dim -gt 0 && $dim == "$bright" ]] || { echo "FAIL: $theme has $dim dim and $bright bright frames" >&2; exit 1; }
  echo "PASS: $theme has $dim frames in each light level"
done
