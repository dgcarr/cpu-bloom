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
