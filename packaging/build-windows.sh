#!/usr/bin/env bash
# Cross-build a portable Windows x64 bundle on Linux. Requires Processing,
# Python 3 and gcc-mingw-w64-x86-64-posix. No Windows Java installation needed.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROCESSING="${PROCESSING:-/opt/processing/bin/Processing}"
OUT="$REPO/dist/windows-x64"
"$PROCESSING" cli --force --sketch="$REPO/cpu_bloom" --output="$OUT" --variant=windows-amd64 --no-java --export
x86_64-w64-mingw32-gcc -Os -s -municode -mwindows "$REPO/packaging/windows-launcher.c" -o "$OUT/cpu_bloom.exe"
python3 - "$REPO" <<'PY'
import hashlib, shutil, sys, urllib.request, zipfile
from pathlib import Path
repo = Path(sys.argv[1])
out = repo / 'dist/windows-x64'
cache = repo / 'dist/windows-jre.zip'
url = 'https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.21%2B9/OpenJDK17U-jre_x64_windows_hotspot_17.0.21_9.zip'
checksum = 'fe4656bd78fb09812dc38c49da777f79cc33e7ee435a254be82f9e7f40d9d117'
if not cache.exists(): urllib.request.urlretrieve(url, cache)
if hashlib.sha256(cache.read_bytes()).hexdigest() != checksum:
    raise SystemExit('Windows JRE checksum mismatch')
with zipfile.ZipFile(cache) as z:
    for item in z.infolist():
        relative = Path(*Path(item.filename).parts[1:])
        if not relative.parts: continue
        dest = out / 'java' / relative
        if item.is_dir(): dest.mkdir(parents=True, exist_ok=True)
        else:
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(item) as src, dest.open('wb') as dst: shutil.copyfileobj(src, dst)
for path in (out / 'lib').glob('*-natives-*.jar'):
    if '-windows-amd64' not in path.name: path.unlink()
shutil.copy(repo / 'packaging/README-Windows.txt', out / 'README-Windows.txt')
shutil.copy(repo / 'LICENSE', out / 'LICENSE.txt')
archive = shutil.make_archive(str(repo / 'dist/cpu-bloom-windows-x64'), 'zip', out.parent, out.name)
print(archive)
PY
