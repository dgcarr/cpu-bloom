"""Assemble notices and accompanying source; fail closed on changed inputs."""
import hashlib
import json
from pathlib import Path
import shutil
import sys
import urllib.request
import zipfile

here = Path(__file__).resolve().parent
repo = here.parent.parent
stage = Path(sys.argv[1])
cache = repo / "dist/license-review"
cache.mkdir(parents=True, exist_ok=True)
sources = stage / "Sources"
sources.mkdir(exist_ok=True)

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()

for item in json.loads((here / "sources.lock.json").read_text()):
    archive = cache / item["file"]
    if not archive.exists():
        temporary = archive.with_suffix(archive.suffix + ".partial")
        with urllib.request.urlopen(item["url"], timeout=120) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        if digest(temporary) != item["sha256"]:
            raise RuntimeError("Source download checksum mismatch: " + item["file"])
        temporary.replace(archive)
    if digest(archive) != item["sha256"]:
        raise RuntimeError("Source checksum mismatch: " + item["file"])
    shutil.copy2(archive, sources / archive.name)

for item in json.loads((here / "licenses/provenance.json").read_text()):
    if digest(here / item["file"]) != item["sha256"]:
        raise RuntimeError("Upstream notice changed: " + item["file"])
shutil.copytree(here / "licenses", stage / "ThirdPartyNotices/upstream", dirs_exist_ok=True)
shutil.copy2(here / "sources.lock.json", sources)
shutil.copy2(here / "SOURCE-AND-RELINKING.md", sources / "README.md")
# Complete application source and packaging scripts; data are already in the package.
with zipfile.ZipFile(sources / "cpu-bloom-source.zip", "w", zipfile.ZIP_DEFLATED) as archive:
    paths = [repo / "LICENSE", repo / "README.md"]
    paths += list((repo / "cpu_bloom").glob("*.pde"))
    paths += list((repo / "cpu_bloom").glob("*.java"))
    paths += [p for p in here.rglob("*") if p.is_file() and "__pycache__" not in p.parts]
    for path in sorted(set(paths)):
        info = zipfile.ZipInfo(path.relative_to(repo).as_posix(), (2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(info, path.read_bytes())
print("Verified notices and accompanying source archives")
