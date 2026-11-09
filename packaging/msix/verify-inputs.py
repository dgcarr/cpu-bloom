"""Validate the pinned build inputs before executing Processing or packaging Java."""
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
lock = json.loads((root / "packaging/msix/inputs.lock.json").read_text())
processing = pathlib.Path(sys.argv[1])
rows = [p.relative_to(processing).as_posix() + "|" + hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(processing.rglob("*")) if p.is_file()]
actual = hashlib.sha256(("\n".join(rows) + "\n").encode()).hexdigest()
if actual != lock["processingTreeSha256"]:
    sys.exit("Processing installation differs from the reviewed 4.5.7 build input")
for name, expected in lock["sourceLibraries"].items():
    path = root / "cpu_bloom/code" / name
    if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
        sys.exit(f"Dependency checksum mismatch: {name}")
if {p.name for p in (root / "cpu_bloom/code").glob("*.jar")} != set(lock["sourceLibraries"]):
    sys.exit("Dependency inventory changed; review and update the lock")
runtime = pathlib.Path(sys.argv[2])
if hashlib.sha256(runtime.read_bytes()).hexdigest() != lock["jreSha256"]:
    sys.exit("Bundled Java archive checksum mismatch")
print("Pinned Processing, source libraries and Java archive verified")
